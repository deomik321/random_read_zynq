# random_read_zynq

ZC702 / Zynq-7000 기준 PL 단독 random read 실험 프로젝트입니다. PS/AXI-Lite 제어 없이 FPGA 내부 master가 미리 저장된 랜덤 주소 trace를 발생시키고, BRAM read engine 앞단에서 burst package의 길이를 조정하는 구조입니다.

## 연구 아이디어

기준 구조는 랜덤 read 요청을 들어온 순서대로 하나씩 처리하되, 각 요청마다 고정 16-beat burst를 발행합니다. 첫 beat만 해당 요청의 useful data로 보고 나머지는 overfetch/discarded data로 카운트합니다.

```text
mode 0: 요청 40개 -> read package 40개 -> 각 package len = 16
```

개선 구조는 BRAM read engine으로 package가 넘어가기 전의 pre-issue window에서 아직 발행되지 않은 기존 package를 봅니다. 새 요청 주소가 기존 base address 기준 16-beat 범위 안에 들어오면, 새 요청을 따로 발행하지 않고 기존 package의 `len`과 `useful_mask`만 갱신합니다. timing closure를 위해 traffic master와 merge unit 사이에는 1-cycle request register slice가 들어갑니다.

```text
처음 A 요청 수신: base=A, len=1
나중에 C=A+60 수신: offset=15, len=16으로 확장
BRAM으로 나가는 최종 package: base=A, len=16
```

중요한 점은 package가 BRAM read engine으로 handshake되기 전까지만 `len`을 바꾼다는 것입니다. 이미 발행된 package의 burst length를 나중에 바꾸는 구조는 아닙니다.

## 실험 모드

| MODE | 의미 | 관찰 포인트 |
|---:|---|---|
| 0 | fixed 16-beat baseline | 요청마다 `len=16` package를 발행하고 첫 beat만 useful로 봄 |
| 1 | range merge, reorder buffer 없음 | burst 수는 줄지만 useful response 순서가 바뀔 수 있음 |
| 2 | range merge, reorder buffer 있음 | burst 수는 줄고 order error는 없어지지만 stall 비용이 생김 |

MODE가 3이면 RTL 내부에서 MODE 2처럼 처리합니다.

## Trace 시나리오

`random_trace_master`는 start 후 총 40개 요청을 8개 시나리오로 발생시킵니다.

| ID | 이름 | 목적 |
|---:|---|---|
| 0 | no merge | 완전히 떨어진 주소는 묶이지 않는지 확인 |
| 1 | late hit | A-B-C에서 C가 A burst range 안으로 들어오는 상황 |
| 2 | multi hit | A 하나에 여러 후속 요청이 붙는 상황 |
| 3 | boundary | A+60은 hit, A+64는 miss |
| 4 | window expired | 주소상 묶을 수 있지만 window가 끝나서 놓치는 상황 |
| 5 | overlap | 여러 pending package 후보가 있을 때 oldest 우선 |
| 6 | dense cluster | 가까운 랜덤 cluster에서 burst 수 감소 |
| 7 | mixed sparse | 일부는 merge, 일부는 독립 burst |

## 주요 카운터

ILA나 시뮬레이션에서 아래 값을 보면 됩니다. 보드 implementation DRC를 줄이기 위해 wide address/mask debug mirror는 기본 mark_debug에서 제외했고, 핵심 성능 카운터 위주로 남겨두었습니다.

```text
mode_cycle_count
mode_input_request_count
mode_burst_count
mode_issued_beat_count
mode_useful_count
mode_discarded_count
mode_merged_count
mode_late_miss_count
mode_output_count
mode_order_error_count
mode_reorder_stall_count
```

해석 기준:

```text
mode_burst_count 감소     -> BRAM read package 수 감소
mode_discarded_count 증가 -> overfetch로 가져왔지만 버린 beat 수
mode_issued_beat_count     -> BRAM에서 실제로 읽은 총 beat 수
mode_useful_count          -> 요청이 실제로 필요로 한 beat 수
mode_order_error_count    -> reorder buffer가 없을 때 순서 깨짐
mode_reorder_stall_count  -> reorder buffer가 순서를 맞추느라 기다린 비용
mode_late_miss_count      -> window가 끝난 뒤 들어와서 못 묶은 요청
```

TB는 아래 보조 지표도 출력합니다.

```text
useful_data_permille  = useful_count / issued_beat_count * 1000
discarded_permille    = discarded_count / issued_beat_count * 1000
discarded_per_request = discarded_count / input_request_count
```

예를 들어 mode 0은 요청마다 무조건 16 beat를 읽기 때문에 요청 40개에서 640 beat를 읽고, 실제 useful beat는 40개뿐입니다. 이 경우 버려지는 beat가 600개라서 waste가 매우 크게 보입니다. 이 프로젝트의 핵심 비교 지표는 단순 cycle count 하나가 아니라 burst 감소, overfetch waste, ordering cost를 함께 보는 것입니다.

## 보드 조작

ZC702 기준 포트 의미:

| 포트 | 용도 |
|---|---|
| `SYSCLK_P/N` | ZC702 200 MHz differential clock |
| `RESETN` | active-low reset |
| `START_N` | active-low start button |
| `MODE[1:0]` | DIP switch 기반 모드 선택 |
| `LED[7:0]` | 상태 확인 |

LED 의미:

| LED | 의미 |
|---:|---|
| 0 | busy |
| 1 | done |
| 2 | pass |
| 3 | active mode bit 0 |
| 4 | active mode bit 1 |
| 5 | merge 발생 |
| 6 | late/window miss 발생 |
| 7 | heartbeat |

## 타이밍 구조

ZC702의 SYSCLK는 200 MHz이지만, 실험용 core는 MMCM으로 만든 100 MHz clock에서 동작합니다. merge unit 내부에 decision register stage를 추가해서 요청 주소 비교와 package 갱신 경로를 나눴습니다. 외부 버튼/DIP/MMCM locked 신호는 Xilinx XPM CDC primitive로 동기화합니다.

현재 구조:

```text
SYSCLK 200 MHz -> IBUFDS -> MMCM -> internal experiment clock 100 MHz
```

reset은 asynchronous assert, synchronous release 방식으로 정리했습니다. 버튼과 DIP switch는 RTL 내부에서 동기화합니다. request register slice가 추가되어 merge window는 7 cycle로 보정되어 있습니다.

## Vivado 실행

Vivado Tcl Console에서:

```tcl
cd C:/Users/USER/Desktop/random_read_zynq
source scripts/create_project.tcl
```

시뮬레이션:

```tcl
source scripts/run_sim.tcl
```

합성/implementation/bitstream:

```tcl
source scripts/run_impl.tcl
```

ILA는 RTL의 `mark_debug` 신호를 기준으로 `scripts/setup_debug_ila.tcl`에서 자동 연결하도록 준비했습니다. 타이밍이 빡빡하면 ILA probe 수나 depth를 줄이는 것이 좋습니다.

## 보드 변경 시 수정할 곳

보드가 바뀌면 아래만 우선 확인하면 됩니다.

```text
constraints/zc702_random_read_zynq.xdc
scripts/create_project.tcl 의 part / board_part
```
