# План: Multi‑Core Passthrough В Одном Процессе (без шардирования/мультипроцесса)

Цель: обслуживать **большое число “обычных” passthrough‑стримов** (типично UDP multicast → UDP multicast) так, чтобы:
- не было 100% на одном ядре,
- нагрузка распределялась по ядрам равномерно,
- стабильность > скорость (нет дерганий/разрывов),
- **без шардирования**, без дополнительных портов для пользователя, **в одном процессе**.

Ограничение: не ломаем пользовательские контракты и конфиги. Новое поведение включается только настройкой.

---

## 0) Что сейчас (и почему одно ядро упирается)

### Поток исполнения
- Один глобальный event loop: `core/event.c` (`event_observer` — static singleton, `asc_event_core_loop()`).
- Глобальные таймеры: `core/timer.c` (heap — static singleton, `asc_timer_core_loop()`).
- Доставка TS синхронная “на каждый пакет”: `modules/astra/module_stream.c::__module_stream_send()` вызывает `on_ts` каждого child.
- UDP input читает один datagram через `asc_socket_recv()` и дальше разрезает на TS и шлёт “пакет‑за‑пакетом”:
  `modules/udp/input.c:on_read()` → `module_stream_send()` в цикле.
- UDP output копит до ~1460 байт и делает `sendto()`:
  `modules/udp/output.c:on_ts()` → `udp_send_packet()` → `asc_socket_sendto()`.

Итог: при большом числе потоков/пакетов почти вся работа делается в одном loop → одно ядро забивается.

---

## 1) Реальный риск: даже идеальный код не даст multi‑core без настройки сети

Если NIC/ядро Linux обрабатывает RX/TX softirq в одном CPU (RSS выключен, одна очередь, IRQ прибит к core0),
то “распараллеливание в userspace” даст ограниченный эффект.

Поэтому в план включаем два слоя:
1) **App‑уровень**: multi‑thread dataplane.
2) **OS‑уровень**: RSS/IRQ/RPS + sysctl (опционально, но для прод‑масштаба почти обязательно).

---

## 2) Оптимальный подход (рекомендую): Control‑Plane (Lua) + Data‑Plane (C workers)

### Идея
- Оставляем текущий Lua/UI/API как “control plane” (надёжно, обратно‑совместимо).
- Добавляем новый “data plane” для **eligible passthrough streams**:
  несколько worker threads внутри процесса, каждый worker обслуживает свою группу стримов.
- Внутри workers:
  - `epoll`/`recvmmsg` для чтения UDP батчами,
  - `sendmmsg` для отправки батчами в несколько outputs,
  - атомарные счётчики и ring‑buffer метрик (без доступа к Lua из worker).
- Пользовательский порт остаётся один (например `:9060`).
- Шардирование/доп. порты не используются.

### Почему это оптимально
- Не требует переписывать весь Lua runtime в multi‑Lua‑states (это огромный риск).
- Даёт реальный multi‑core на “массовых” passthrough каналах.
- Включается флагом и применяется “только если поток простой” → минимальный риск для функционала.

---

## 3) Критерии “eligible passthrough stream”

Data‑plane включаем только если конфиг стрима “простой”:
- input: UDP/RTP (первый этап) *(позже можно добавить SRT/HTTP‑TS)*,
- output: UDP/RTP,
- `transcode.enabled=false`,
- `softcam` не включён,
- нет remap/service‑операций, нет mpts,
- backup/failover выключен (на первом этапе),
- quality detectors выключены (на первом этапе),
- нет “audio fix”.

Если поток не подходит — запускаем **старый pipeline**, без изменений.

---

## 4) Настройки (только opt‑in)

Реализовано через settings (только opt‑in, дефолты безопасные):
```json
{
  "settings": {
    "performance_passthrough_dataplane": "off|auto|force",
    "performance_passthrough_workers": 0,
    "performance_passthrough_rx_batch": 32,
    "performance_passthrough_affinity": false,

    "performance_udp_batching": false,
    "performance_udp_rx_batch": 32,
    "performance_udp_tx_batch": 32
  }
}
```

Рекомендации по дефолтам:
- `performance_passthrough_dataplane="off"` (безопасно).
- `performance_passthrough_workers=0` → авто: `max(1, min(cores-1, 32))`.
- `performance_passthrough_affinity=false` (пининг потоков только по явному включению).

---

## 5) Архитектура Data‑Plane (внутри процесса)

### Компоненты
1) `passthrough_engine` (C)
   - хранит `worker[N]`
   - хранит `stream_ctx` для каждого eligible stream
2) `worker thread`
   - собственный `epoll_fd`
   - `eventfd` для команд (add/remove/update stream)
   - цикл:
     - drain commands
     - `epoll_wait`
     - `recvmmsg` по ready sockets
     - обработка batched TS (проверка 0x47, выравнивание по 188/1316 при необходимости)
     - `sendmmsg` в outputs
3) `control plane adapter` (Lua bindings)
   - создаёт/удаляет `stream_ctx` при apply config
   - отдаёт status API из атомарных метрик

### Распределение стримов по workers
Стабильное и простое:
- `worker_index = fnv1a(stream_id) % workers`
- Плюс “least loaded” только для новых стримов (опционально).

### Метрики
Пер‑стрим (atomic):
- bytes_in, bytes_out
- pkts_in, pkts_out
- drops_sendq (ENOBUFS/EAGAIN)
- last_rx_ts_monotonic
- last_err_errno (rate limited)

Глобально:
- per_worker active_streams
- per_worker epoll_wakeups
- total_drops

Эти метрики отображаем в UI/API как часть stream status (только для dataplane streams).

---

## 6) План внедрения (по шагам, минимальный риск → максимальный эффект)

### Шаг A (P0): Снять нагрузку без потоков исполнения
Цель: улучшить ситуацию даже без multi‑core, чтобы уменьшить риск.
- Добавить `recvmmsg`/`sendmmsg` в UDP input/output как opt‑in:
  - `modules/udp/input.c`: batched receive
  - `modules/udp/output.c`: batched send
  - опция: `settings.performance.udp_batching=on`
- Уменьшить “вызовов на пакет”:
  - в input: быстрее резать datagram 1316 и отправлять пакетами, но без лишних проверок.
  - (опционально) добавить `module_stream_send_batch(stream, ptr, count)` — но это уже глубокий рефактор.

Acceptance:
- CPU на 200 потоках падает заметно (perf top/strace -c).

### Шаг B (P1): Data‑Plane для UDP→UDP (основной multi‑core)
- Реализовать `modules/passthrough/engine.c` + Lua binding `passthrough_engine`.
- В `scripts/stream.lua:make_channel()` добавить ветку:
  - если `passthrough_dataplane=auto/force` и поток eligible → создаём dataplane stream
  - иначе → старый make_channel
- Реализовать корректный stop/reload:
  - kill_channel должен закрывать dataplane stream (через binding).
- Реализовать status:
  - `runtime.list_status()` / stream status берёт метрики из dataplane.

Acceptance:
- При 200+ passthrough streams CPU распределяется по cores (mpstat).
- Нет дерганий (потери/гепы ниже baseline).
- Отключение dataplane возвращает к старому поведению.

### Шаг C (P1.5): OS‑уровень рецепт (в manual + installer)
Не код, но важно для результата:
- проверка RSS:
  - `ethtool -l <iface>`
  - `ethtool -x <iface>`
- включить irqbalance или вручную разнести IRQ по cores
- при необходимости включить RPS (если RSS нет)
- sysctl:
  - `net.core.rmem_max`, `net.core.wmem_max`
  - `net.ipv4.udp_rmem_min`, `net.ipv4.udp_wmem_min`
  - `net.core.netdev_max_backlog`

Acceptance:
- На типовом сервере без тюнинга тоже работает, но с тюнингом достигает “ровных” графиков CPU.

### Шаг D (P2): Расширение eligible‑функций
Если понадобится:
- backup Active (без warm inputs) внутри dataplane:
  - два input сокета, переключение по no‑data timeout
  - return на “предыдущий” (по цепочке) после stable_ok_sec + return_delay
- basic CC/bitrate анализ (без тяжёлых таблиц), только counters.

---

## 7) Тест‑план (обязательно для стабильности)

### Функциональные
1) `passthrough_dataplane=off` → регрессии нет.
2) `auto`:
   - eligible поток уходит в dataplane,
   - не eligible остаётся в legacy.
3) enable/disable стрима, update outputs, restart сервиса — без утечек и зависаний.

### Perf/Soak
Сценарии (на стенде):
- 200 streams UDP→UDP, pkt_size=1316, 5–8 Мбит каждый.
- 500 streams (если железо позволяет).
- `mpstat -P ALL 1` + `pidstat -t -p PID 1`
- `perf top` / `perf record -g`
- сетевые дропы: `/proc/net/softnet_stat`, `netstat -su`

Критерии:
- нет “всё на одном core”,
- p95 задержки API не растут,
- drops стабильны (не растут со временем),
- RSS процесса стабилен (нет линейного роста).

---

## 8) Риски и как их закрывать

1) **Параллельный доступ к Lua/статусам**: workers не должны трогать Lua.
   Решение: только atomic метрики + команды через очереди/eventfd.
2) **Сложные функции (remap/mpts/softcam)**: в dataplane не поддерживаем на первом этапе.
   Решение: “eligible only” + явный reason в UI (“legacy pipeline: remap enabled”).
3) **Сеть/IRQ**: без RSS всё равно может быть перекос по CPU.
   Решение: manual+диагностика+рекомендации.

---

## 9) Что НЕ делаем в этом плане (осознанно)
- Не переписываем весь runtime на multi‑Lua‑states (слишком рискованно).
- Не включаем dataplane по умолчанию.
- Не ломаем текущие форматы stream config.
