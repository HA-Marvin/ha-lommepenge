# Lommepenge app API (Home Assistant ⇄ app)

This is the contract between the Lommepenge integration in Home Assistant (the
server) and the Android app (the client). The app is a **pure view of HA**: it
stores no history, applies no rules and keeps only HA's latest response in
memory. Every action needs a connection and takes effect only when HA has
confirmed it. There is no offline queue.

All endpoints live under `/api/lommepenge` on HA's local address (for example
`http://192.168.1.10:8123/api/lommepenge`) and only answer requests from the
home network. HA's own users and tokens are never used.

| Method | Path | Signed | Purpose |
| --- | --- | --- | --- |
| `POST` | `/api/lommepenge/pair` | no | Exchange a pairing code for the device's key |
| `GET` | `/api/lommepenge/state` | yes | The current state |
| `POST` | `/api/lommepenge/action` | yes | Perform an action; returns the new state |
| `GET` | `/api/lommepenge/history` | yes | History, 30 days per page |
| `GET` | `/api/lommepenge/apk` | yes | The newest APK (app update) |

The install page, QR code and first-time APK download
(`/api/lommepenge`, `/install/{code}`, `/qr/{code}.svg`, `/download/{code}/…`,
`/app.apk`) are for browsers and are not described here.

## Conventions

- **JSON** everywhere, UTF-8. The app must ignore fields it does not know; new
  fields can be added at any time.
- **Amounts** are integers in 1/100 of the family's currency (`…Ore` fields,
  e.g. `500` = 5.00). The currency text is in `state.currency` (e.g. `"DKK"`).
- **Times** (`now`, `deadline`, `completedAt`, `at`, …) are HA's **local** time
  as ISO 8601 **without** a UTC offset and with milliseconds, e.g.
  `"2026-11-23T18:00:00.000"`. Show them as they are; do not convert time zones.
- **Dates** are `"YYYY-MM-DD"` in HA's local time. Times of day are `"HH:MM"`.
- **Ids** are strings. Ids the app creates (completions, tasks, children,
  adjustments) should be UUID v4 and at most 100 characters.
- **Language:** send the app's chosen language in `X-Lommepenge-Language`
  (`en`, `da`, `de`, `es`, `fr`) on every request; HA writes `error` texts,
  lock reasons (`lock.reason`, history `note`) and notification `message`s in
  that language.

## Signing

Every signed request carries these headers:

| Header | Value |
| --- | --- |
| `X-Device-Id` | `deviceId` from pairing |
| `X-Timestamp` | Unix time in seconds (corrected, see below) |
| `X-Signature` | lowercase hex HMAC-SHA256, see below |
| `X-App-Version` | e.g. `0.5.0` (optional, shown in HA) |
| `X-App-Version-Code` | e.g. `500` (optional, used for updates) |
| `X-Lommepenge-Language` | the app's language (optional) |

The signature is `HMAC-SHA256(key = deviceKey as UTF-8, message)` where

```
message = timestamp + "\n" + METHOD + "\n" + pathAndQuery + "\n" + body
```

- `METHOD` is upper case (`GET`, `POST`).
- `pathAndQuery` is the request target **exactly as sent**, including the query
  string if there is one, e.g. `/api/lommepenge/history?before=2026-10-25`.
  Build query strings yourself from the parameters below (their values only
  contain `A–Z a–z 0–9 - _ ,`) so that the bytes you sign are the bytes sent.
- `body` is the raw request body (empty for `GET`).

A request older or newer than 5 minutes (by HA's clock) is refused with
`clock_skew`.

**Clock correction.** Every 401 response contains `serverTime` (HA's Unix time
in seconds). On `clock_skew` the app stores `offset = serverTime - deviceTime`,
signs with `deviceTime + offset` from then on, and retries once. A wrong clock
must never lead to a new pairing.

## Errors

Every error response from the endpoints above is JSON:

```json
{ "error": "The task cannot be marked as done right now.", "code": "task_not_available" }
```

`error` is a human-readable text for the user (in the app's language). `code`
is stable; the app decides what to do from the HTTP status and `code` only.

| Status | `code` | Meaning / what the app does |
| --- | --- | --- |
| 400 | `invalid_request` | Malformed request (pair body, history query). |
| 400 | `invalid_action` | The action body is not a JSON object. |
| 400 | action error, see [Action errors](#action-errors) | The action is not valid in the current state. Show `error`; nothing changed. |
| 401 | `device_not_connected` | Unknown or revoked device: forget the pairing and show "Connect to Home Assistant". |
| 401 | `invalid_signature` | Wrong key: same as above. |
| 401 | `missing_timestamp` | Bug in the app (no/invalid `X-Timestamp`). |
| 401 | `clock_skew` | Correct the clock with `serverTime` and retry. Never unpair. |
| 403 | `forbidden_action` | The device's role may not do this (e.g. a child's tablet). |
| 404 | – | Not found (APK not fetched yet: `app_not_fetched`). |
| 410 | `pairing_invalid` | Pairing code wrong, expired or used. |
| 413 | `request_too_large` | Body over 64 KiB. |
| 429 | `too_many_pairings` | Too many wrong codes; wait five minutes. |
| 502 | – | HA could not fetch the APK from GitHub (`app_fetch_failed`). |

401 responses additionally have `"serverTime": 1795442400`.

Two responses are **plain text**, not JSON: `403` *Only available on the home
network* (request not from the local network) and `503` *Lommepenge is not set
up* (integration not loaded). The APK errors (404/502) are plain text too.
Treat any non-JSON response or a network failure/timeout as "No connection to
Home Assistant – try again" and change nothing locally.

## Pairing

`POST /api/lommepenge/pair` (not signed)

```json
{ "token": "ABCD2345", "appVersion": "0.5.0", "appVersionCode": 500 }
```

`token` is the 8-character code from *Add device* in HA (case, spaces and
dashes are ignored). Response `200`:

```json
{
  "deviceId": "8c0f…",
  "deviceKey": "64 hex characters",
  "role": "child",
  "childId": "emma-uuid",
  "deviceName": "Emma's tablet",
  "familyName": "The Family"
}
```

`role` is `screen` (family screen), `parent` (parent's phone) or `child`
(child's tablet, with `childId`). Errors: `400 invalid_request`,
`410 pairing_invalid`, `429 too_many_pairings`.

## State

`GET /api/lommepenge/state` (signed). Poll every 30 seconds and when the app
comes to the foreground. The same object is returned by every successful
action.

### Child's tablet (`role = child`)

```json
{
  "familyName": "The Family",
  "now": "2026-11-23T12:00:00.000",
  "today": "2026-11-23",
  "children": [
    {
      "id": "emma-uuid",
      "name": "Emma",
      "sortOrder": 0,
      "balanceOre": 2500,
      "earnedThisWeekOre": 1000,
      "tasks": [
        {
          "taskId": "t1",
          "title": "Empty the dishwasher",
          "description": null,
          "amountOre": 500,
          "recurrence": "daily",
          "mandatory": true,
          "startTime": null,
          "dueTime": null,
          "date": "2026-11-23",
          "deadline": "2026-11-23T18:00:00.000",
          "status": "available",
          "completionId": null,
          "late": false,
          "forfeited": false
        }
      ],
      "lock": {
        "status": "running",
        "reason": "Missing: Empty the dishwasher (due 18:00)",
        "reasons": [
          {
            "kind": "overdue",
            "taskId": "t1",
            "taskTitle": "Empty the dishwasher",
            "date": "2026-11-23",
            "deadline": "2026-11-23T18:00:00.000",
            "reason": null,
            "absorbed": false
          }
        ],
        "minutes": 60,
        "pendingSince": "2026-11-23T18:00:30.000",
        "pendingUntil": null,
        "startedAt": "2026-11-23T18:20:00.000",
        "endsAt": "2026-11-23T19:20:00.000"
      },
      "paused": false,
      "pausedUntil": null,
      "notifications": [
        {
          "id": "n-uuid",
          "type": "lockStarted",
          "at": "2026-11-23T18:20:00.000",
          "taskId": null,
          "taskTitle": null,
          "date": null,
          "deadline": null,
          "reason": "Missing: Empty the dishwasher (due 18:00)",
          "minutes": 60,
          "endsAt": "2026-11-23T19:20:00.000",
          "message": "The tablet is locked for 60 minutes. Missing: Empty the dishwasher (due 18:00)"
        }
      ]
    }
  ],
  "currency": "DKK",
  "device": { "id": "8c0f…", "name": "Emma's tablet", "role": "child", "childId": "emma-uuid" },
  "appUpdate": { "version": "0.5.0", "versionCode": 500, "sha256": "…", "size": 21345678 }
}
```

`children` contains only the tablet's own child, with its `lock` (see
[Locks](#locks)), `paused`/`pausedUntil` (see [Pause](#pause)) and its
`notifications` (see [Notifications](#notifications)). `appUpdate` is `null`
when HA has not fetched a release.

### Family screen and parent's phone (`role = screen | parent`)

The same fields, with **all** children in `children` (sorted) – each with
`lock`, `paused` and `pausedUntil`, but **without** `notifications` (those are
only for the child's tablet) – plus:

```json
{
  "approvals": [
    {
      "completionId": "app-uuid",
      "childId": "emma-uuid",
      "childName": "Emma",
      "taskId": "t1",
      "taskTitle": "Empty the dishwasher",
      "amountOre": 500,
      "completedAt": "2026-11-23T18:20:00.000",
      "late": true
    }
  ],
  "tasks": [
    {
      "id": "t1",
      "title": "Empty the dishwasher",
      "description": null,
      "amountOre": 500,
      "recurrence": "daily",
      "mandatory": true,
      "activeWeekdays": [1, 2, 3, 4, 5],
      "assignedChildIds": null,
      "startTime": null,
      "dueTime": "17:30",
      "showInCalendar": false,
      "createdAt": "2026-11-01T10:00:00.000"
    }
  ],
  "settings": {
    "defaultDueTime": "18:00",
    "lockMinutes": 60,
    "latePauseMinutes": 10,
    "warningMinutes": 60,
    "winterFromWeek": 43,
    "winterToWeek": 13
  },
  "pinHash": "…",
  "pinSalt": "…"
}
```

- `approvals`: pending completions, oldest first (the approval page).
- `tasks`: the active tasks with all fields, for the edit screens.
  `activeWeekdays` is `null` (every day) or ISO weekdays 1 = Monday … 7 = Sunday.
  `assignedChildIds` is `null` (all children) or a list of child ids.
- `settings`: see `set_setting`. The old `restrictionStart`/`restrictionEnd`
  are gone.
- `pinHash`/`pinSalt`: the parent PIN for the family screen's parent mode.
  A PIN is correct when `lowercase hex SHA-256(UTF-8 of pinSalt + ":" + pin)`
  equals `pinHash`. **Only sent to the family screen** (Del H5): a parent's
  phone opens parent mode without a PIN, and a child's tablet has no parent
  mode.

### Task entries (`children[].tasks`)

HA calculates one entry **per task** for the child, sorted by `date`, then
status (overdue, available, awaiting approval, upcoming), then deadline, then
title. The app shows them as they are and calculates nothing.

| Field | Meaning |
| --- | --- |
| `taskId`, `title`, `description`, `recurrence`, `startTime`, `dueTime` | From the task. `recurrence`: `once`, `daily`, `weekly`, `unlimited`. |
| `mandatory` | From the task – but `false` for every task while the child is [paused](#pause). |
| `amountOre` | What the task gives now (for a pending completion: what it gave when it was done). `0` when `forfeited`. |
| `date` | The day of this occurrence. |
| `deadline` | When the occurrence is late, or `null` (optional tasks have no deadline). `dueTime` of the task, else `settings.defaultDueTime`, on `date`. |
| `status` | `available`, `overdue`, `awaitingApproval` or `upcoming`. |
| `completionId` | The pending completion when `awaitingApproval`, else `null`. |
| `late` | `true` when the pending completion was done after the deadline. |
| `forfeited` | `true` for an `overdue` entry whose lock has run out: doing it now gives no money (`amountOre` is `0`). |

Status:

- `available` – can be marked as done now (button enabled).
- `overdue` – the deadline has passed; it can still be marked as done (the
  completion is then `late`). Disappears at midnight if not done. See
  [Locks](#locks) for what lateness costs.
- `awaitingApproval` – done, waiting for a parent. One entry stays until it is
  handled.
- `upcoming` – a later day within the horizon; cannot be marked as done yet.

Rules HA applies (for understanding; the app does not repeat them):

- **Horizon:** entries are only sent for `today` and the next 4 days (5
  calendar days). A task whose next occurrence is further away is not in the
  list at all.
- **Approved or rejected** → the entry moves on to the task's next normal
  occurrence (daily: the next active day; weekly: 7 days after the day it was
  done). A rejected **one-off** task becomes `available` again; an approved one
  is gone.
- **Weekly** = 7 rolling days after the day the last handled completion was
  done, or after a missed deadline.
- **Unlimited** tasks are always `available` (one pending at a time). A
  mandatory one has a deadline until it has been done that day.
- A **one-off** task can be done before its `date`; its deadline is the first
  deadline after it was created.
- A new task (or new child) is never overdue at once: an occurrence whose
  deadline had passed before the task existed is skipped.
- **Midnight:** every late, not done occurrence is removed without money and
  recorded as `missed` in the history. A missed one-off task is gone for good
  (a parent must create it again). A missed weekly task returns 7 days after
  the missed deadline. Awaiting-approval entries are never removed.

## Locks

HA decides everything about locks; the app only shows `children[].lock` and,
on the child's tablet, reports use (`report_use`) and shows a countdown.

| Field | Meaning |
| --- | --- |
| `status` | `none`, `pending` (waits for the child to use the tablet) or `running`. |
| `reason` | Ready-made text for all causes, in the app's language, e.g. `Missing: Empty the dishwasher (due 18:00); Rejected: Tidy up`. `null` when `none`. Show it under the countdown. |
| `reasons` | The causes, oldest first: `kind` (`overdue`, `rejected` or `late`), `taskId`, `taskTitle`, `date` (the occurrence), `deadline`, `reason` (the parent's reason for a rejection, else `null`), `absorbed` (`true` = arrived while the lock was running and did not extend it). |
| `minutes` | How long it runs (`running`) or will run when it starts (`pending`). |
| `pendingSince` | When the lock was caused. |
| `pendingUntil` | `pending` only: when it lapses unstarted (24 hours after `pendingSince`). |
| `startedAt`, `endsAt` | `running` only: start and end. **Countdown = `endsAt` − `now`** (use `state.now`, HA's time, not the tablet's clock; count down locally between polls). |

When `status` is `none` all other fields are `null` and `reasons` is `[]`.
A `running` lock whose `endsAt` has passed is already reported as `none`.
Lock types other than the network rule (e.g. an overlay on other apps) may
be added later as new fields; ignore what you do not know.

Rules HA applies (for understanding):

- **Causes:** a mandatory task becomes `overdue`, or a mandatory task is
  rejected (`reject_completion`).
- **Every lock waits** until the child's tablet reports use (`report_use`
  with `screen_on` or `user_present`). Then it runs `minutes` and ends by
  itself. A pending lock lapses 24 hours after it was caused.
- **Duration:** `settings.lockMinutes` (default 60). If the late task is done
  while the lock is still pending, its cause becomes `late` and – when all
  causes are `late` – the lock runs only `settings.latePauseMinutes`
  (default 10; `0` = no lock). The task still earns money.
- **Money:** a late task done while its lock is pending or running earns its
  amount. Once the lock has **run out**, the task is `forfeited`: done after
  that it gives `0`, and the child gets a `forgotten` notification at that
  moment.
- **One lock at a time:** new causes join a pending lock; causes that arrive
  while a lock runs are absorbed (no new lock, no extension, and they are
  forfeited when that lock runs out). One penalty per task occurrence – an
  occurrence never locks twice, not even after the lock was lifted.
- **Midnight:** a late task is removed as usual; a lock that has not started
  yet stays pending (and still lapses 24 hours after it was caused).
- **Lift lock** (`lift_lock`, parents) clears the pending or running lock.
  New causes can lock again.
- The tablet must be online to be locked; HA turns the network rule on only
  while `status` is `running`.

## Pause

`children[].paused` is `true` while the child is paused, and `pausedUntil` is
the date the pause ends (`"YYYY-MM-DD"`, tasks are mandatory again from 00:00
that day) or `null` (until a parent resumes). While paused, no task is
mandatory: no deadline, never `overdue`, no lock – but tasks still earn
money. When the pause ends, the tasks start over (nothing from during the
pause becomes overdue). Set with `set_pause`; pausing also lifts the lock.

## Notifications

The child's tablet gets `children[0].notifications` in every state response:
the child's notifications from the last **7 days**, newest first. There is no
read state; HA deletes them after 7 days. There is no separate endpoint – the
foreground service polls `GET /state` and shows an Android notification for
each `id` it has not shown before (remember the shown ids on the device; they
are unique).

| Field | Meaning |
| --- | --- |
| `id` | Unique id. |
| `type` | See below. |
| `at` | When it happened (HA's time). |
| `message` | Ready-made text in the app's language – show this. |
| `taskId`, `taskTitle`, `date`, `deadline` | The task occurrence, when the type has one (`taskTitle` as it was then). |
| `reason` | `rejected`: the parent's reason (or `null`). `lockStarted`: the lock's reason text. Otherwise `null`. |
| `minutes`, `endsAt` | `lockStarted` only. |

| `type` | When |
| --- | --- |
| `deadlineWarning` | `settings.warningMinutes` before the deadline of a mandatory task that is not done (once per occurrence; `0` = never). |
| `overdue` | A mandatory task's deadline has passed (once per occurrence). |
| `rejected` | A parent rejected a completion (any task), with the optional reason. |
| `lockStarted` | A lock started (the tablet was used while a lock was pending). |
| `forgotten` | A lock ran out and its task is still not done: it gives no money today. |

While the child is paused only `rejected` can occur.

## Actions

`POST /api/lommepenge/action` (signed), body:

```json
{ "type": "complete_task", "payload": { "taskId": "t1", "childId": "emma-uuid", "completionId": "app-uuid" } }
```

On success the response is `200` with the **new state** (exactly as
`GET /state` for this device). The app shows a spinner while waiting and
updates the screen from this response only; on an error or no connection it
changes nothing locally.

A child's tablet may only send `complete_task` and `report_use` for its own
child; everything else gives `403 forbidden_action`. `report_use` is only for
a child's tablet (`403` from the family screen and parents' phones).

| `type` | `payload` | Notes |
| --- | --- | --- |
| `complete_task` | `taskId`, `childId`, `completionId` | Idempotent, see below. HA's clock decides the time and `late`. |
| `approve_completion` | `completionId` | Parent. |
| `approve_completions` | `completionIds` (non-empty list) | Parent. "Approve all" (Del H5): approves exactly the listed completions – the ones the parent saw – so one that arrived meanwhile stays pending. All or nothing: an unknown id → `400 completion_not_found`, one rejected meanwhile → `400 completion_already_handled`, and then nothing is approved. |
| `reject_completion` | `completionId`, `reason` (optional text, max 500 characters) | Parent. The child gets a `rejected` notification with the reason; a mandatory task causes a lock. |
| `create_task` | `id`, `title`, `amountOre`, `recurrence`, `mandatory`, `description`, `activeWeekdays`, `assignedChildIds`, `startTime`, `dueTime`, `showInCalendar` | `title` and integer `amountOre` ≥ 0 required. Unknown `recurrence` → `once`. `once` ignores `activeWeekdays`. |
| `update_task` | `id` + the same fields | `title`, `amountOre` required. A missing key keeps the old value; explicit `null` clears it (`activeWeekdays`, `assignedChildIds`, `startTime`, `dueTime`). `description` is always replaced. |
| `delete_task` | `id` | Deactivates the task (history keeps it). |
| `add_child` | `id`, `name` | |
| `rename_child` | `id`, `name` | |
| `delete_child` | `id` | |
| `adjust_balance` | `id`, `childId`, `amountOre` (may be negative), `note` (required) | |
| `mark_paid_out` | `childId` | Balance becomes 0. |
| `set_setting` | `key`, `value` | Keys: `defaultDueTime` (`"HH:MM"`), `lockMinutes` (1–480), `latePauseMinutes` (0–240), `warningMinutes` (0–600), `winterFromWeek`/`winterToWeek` (1–53). |
| `report_use` | `childId`, `event` (`screen_on` or `user_present`), `at` (optional, the tablet's Unix time in seconds) | **Child's tablet only.** Send on Android's `SCREEN_ON` and `USER_PRESENT`. Starts a pending lock now (by HA's clock; `at` is only recorded). Without a pending lock nothing happens. Returns the new state, so the countdown can start at once. |
| `lift_lock` | `childId` | Parent. Clears the child's pending or running lock. |
| `set_pause` | `childId`, `paused` (bool), `until` (optional `"YYYY-MM-DD"`, after today) | Parent. `paused: true` pauses (or changes `until`; missing/`null` = no end date) and lifts the lock; `paused: false` resumes now. |

`suspend_restriction` (`childId`) from the old restriction model still works
as an alias for `lift_lock`; do not use it in new code.

### Idempotency (retries)

The app may resend an action after a timeout or lost response. HA guarantees:

- `complete_task` with a `completionId` HA already knows returns `200` and the
  current state **without** creating another completion – also if that
  completion has since been approved or rejected. Therefore the app creates
  the `completionId` (UUID v4) **once per tap** and reuses it for every retry
  of that tap.
- `approve_completion`/`reject_completion` with the same answer again → `200`,
  no change (also when the other parent answered the same). The opposite
  answer after a decision → `400 completion_already_handled` (the first answer
  counts).
- `approve_completions` with ids that are already approved → `200`, no change
  for those (a retry approves nothing twice).
- `create_task`, `add_child`, `adjust_balance` with an `id` that already exists
  do not create duplicates (`create_task` replaces the fields; the original
  creation time is kept). Always send an app-made `id`.
- `delete_task`, `delete_child`, `update_task`, `rename_child`,
  `mark_paid_out`, `set_setting`, `lift_lock`, `set_pause` and `report_use`
  can safely be repeated (a repeated `report_use` does not restart or extend a
  running lock).

### Action errors

All `400` with the `code` below (text in `error`):

| `code` | When |
| --- | --- |
| `unknown_action` | Unknown `type`. |
| `missing_field` | A required field is missing/invalid (e.g. `amountOre`, `completionId` over 100 characters, `report_use` `event`, `set_pause` `paused`). |
| `missing_id`, `missing_child_id`, `missing_task`, `missing_completion`, `missing_setting` | The named field is missing. |
| `task_title_required`, `negative_amount`, `child_name_required`, `adjustment_note_required` | Validation. |
| `task_not_found` | The task does not exist or is deleted/missed. |
| `task_not_assigned` | The task is not for this child. |
| `task_not_available` | The entry is `upcoming` or `awaitingApproval`, or a done one-off task. |
| `completion_not_found`, `completion_already_handled` | See idempotency. |
| `child_not_found` | Unknown child. |
| `invalid_time`, `setting_out_of_range`, `unknown_setting` | `set_setting`. |
| `invalid_pause_until` | `set_pause` with an `until` that is not a date after today. |

## History

`GET /api/lommepenge/history` (signed). Fetched when the history page is
opened and never stored on the device.

Query parameters (all optional):

| Parameter | Meaning |
| --- | --- |
| `before` | `YYYY-MM-DD`, exclusive end of the page. Default: tomorrow (the page includes today). |
| `childId` | Only this child. A child's tablet always gets only its own child; asking for another child gives `403 forbidden_action`. |
| `types` | Comma-separated filter, e.g. `approved,rejected`. Allowed: `approved`, `rejected`, `adjustment`, `missed`, `lock`. An unknown type gives `400 invalid_request`. |

Remember that the query string is part of the signed path.

Response `200`:

```json
{
  "from": "2026-10-25",
  "before": "2026-11-24",
  "items": [
    {
      "id": "app-uuid",
      "type": "approved",
      "at": "2026-11-23T19:02:11.000",
      "childId": "emma-uuid",
      "childName": "Emma",
      "taskId": "t1",
      "taskTitle": "Empty the dishwasher",
      "amountOre": 500,
      "completedAt": "2026-11-23T18:20:00.000",
      "late": true,
      "note": null
    }
  ],
  "nextBefore": "2026-10-25"
}
```

- A page covers the 30 days `from` ≤ day < `before`, newest first.
- **"Show older"** = request again with `before = nextBefore`. `nextBefore` is
  `null` when nothing older exists (hide the button). A page can be empty while
  `nextBefore` is not `null` (a quiet month).
- Item types:

| `type` | `at` | Fields |
| --- | --- | --- |
| `approved` | when it was approved | task fields, `amountOre`, `completedAt`, `late` |
| `rejected` | when it was rejected (older data: when it was done) | as `approved`; gave no money; `note` = the parent's reason (or `null`) |
| `adjustment` | when it was made | `amountOre` (signed), `note`; `taskId`/`taskTitle`/`completedAt` are `null` |
| `missed` | the missed deadline | task fields, `amountOre` it would have given; `completedAt` is `null` |
| `lock` | when the lock started, ended or was lifted | `lockEvent` (`started`, `ended` or `lifted`), `minutes`, `reasons` (as in [Locks](#locks)), `note` = the reason text; `taskId`/`taskTitle`/`completedAt` are `null`, `amountOre` is `0` |

A lock that ran gives two items (`started`, then `ended` or `lifted`); a lock
lifted while pending gives only `lifted`. Pending locks that lapsed are not
in the history. Lock item ids are `<lockId>-<lockEvent>`.

`childName`/`taskTitle` are the current names (empty string / `null` if the
child or task no longer exists). Pending completions are not history (they
are in `approvals` and the task entries). There is no payout history.

## App update

`GET /api/lommepenge/apk` (signed) streams the APK described by
`state.appUpdate`. Check its SHA-256 against `appUpdate.sha256` before
installing.
