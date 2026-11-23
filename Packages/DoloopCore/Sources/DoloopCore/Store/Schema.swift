import GRDB

/// 변경 기록으로 다시 만들 수 있는 표. 표 이름을 그대로 쓴다.
enum ChangeEntity: String, CaseIterable {
    case task
    case taskCompletion = "task_completion"
    case routine
    case routineVersion = "routine_version"
    case routineRecord = "routine_record"
}

enum Schema {
    /// 기기끼리 기록이 순서 없이 도착해도 합칠 수 있도록 외래 키를 두지 않는다. 참조는 저장소 API가 확인한다.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: v1)
        }
        return migrator
    }

    private static let dayPattern = "'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'"

    private static let v1 = """
    CREATE TABLE change_log (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        change_id TEXT NOT NULL UNIQUE,
        device_id TEXT NOT NULL CHECK (length(device_id) > 0),
        timestamp INTEGER NOT NULL,
        entity TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        field TEXT NOT NULL,
        value ANY
    ) STRICT;
    CREATE INDEX change_log_field ON change_log (entity, entity_id, field, timestamp);
    CREATE INDEX change_log_timestamp ON change_log (timestamp);
    CREATE TRIGGER change_log_no_update BEFORE UPDATE ON change_log
    BEGIN SELECT RAISE(ABORT, 'change_log is append-only'); END;
    CREATE TRIGGER change_log_no_delete BEFORE DELETE ON change_log
    BEGIN SELECT RAISE(ABORT, 'change_log is append-only'); END;

    CREATE TABLE task_list (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color TEXT,
        folder_id TEXT,
        view_mode TEXT NOT NULL DEFAULT 'list',
        sort_order REAL NOT NULL DEFAULT 0,
        deleted_at INTEGER
    ) STRICT;

    CREATE TABLE tag (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color TEXT,
        parent_id TEXT,
        deleted_at INTEGER
    ) STRICT;

    CREATE TABLE task (
        id TEXT PRIMARY KEY,
        list_id TEXT,
        parent_id TEXT,
        title TEXT NOT NULL CHECK (length(title) > 0),
        note TEXT NOT NULL,
        schedule TEXT NOT NULL,
        due_day TEXT CHECK (due_day IS NULL OR due_day GLOB \(dayPattern)),
        weight TEXT NOT NULL CHECK (weight IN ('heavy', 'light')),
        repeat_rule TEXT,
        completed_day TEXT CHECK (completed_day IS NULL OR completed_day GLOB \(dayPattern)),
        created_at INTEGER NOT NULL,
        deleted_at INTEGER
    ) STRICT;
    CREATE INDEX task_due_day ON task (due_day);

    CREATE TABLE task_completion (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        day TEXT NOT NULL CHECK (day GLOB \(dayPattern)),
        completed_at INTEGER,
        UNIQUE (task_id, day)
    ) STRICT;

    CREATE TABLE checklist_item (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        title TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0 CHECK (done IN (0, 1)),
        sort_order REAL NOT NULL DEFAULT 0,
        deleted_at INTEGER
    ) STRICT;

    CREATE TABLE reminder (
        id TEXT PRIMARY KEY,
        owner_type TEXT NOT NULL CHECK (owner_type IN ('task', 'routine')),
        owner_id TEXT NOT NULL,
        rule TEXT NOT NULL,
        deleted_at INTEGER
    ) STRICT;

    CREATE TABLE routine (
        id TEXT PRIMARY KEY,
        start_day TEXT NOT NULL CHECK (start_day GLOB \(dayPattern)),
        finish_day TEXT CHECK (finish_day IS NULL OR finish_day GLOB \(dayPattern)),
        archived_at INTEGER,
        created_at INTEGER NOT NULL,
        deleted_at INTEGER
    ) STRICT;

    CREATE TABLE routine_version (
        id TEXT PRIMARY KEY,
        routine_id TEXT NOT NULL,
        valid_after TEXT NOT NULL CHECK (valid_after GLOB \(dayPattern)),
        -- 바꾼 필드만 저장한다. NULL은 앞 버전의 값을 그대로 쓴다는 뜻이다.
        title TEXT CHECK (title IS NULL OR length(title) > 0),
        cue TEXT,
        group_id TEXT,
        schedule TEXT,
        -- 반복 규칙과 기준일이 따로 합쳐져 어긋나지 않도록 `기준일|규칙`으로 묶는다.
        repeat_plan TEXT,
        max_count_per_day INTEGER CHECK (max_count_per_day IS NULL OR max_count_per_day >= 1),
        mini_title TEXT,
        max_title TEXT,
        UNIQUE (routine_id, valid_after)
    ) STRICT;

    CREATE TABLE routine_record (
        id TEXT PRIMARY KEY,
        routine_id TEXT NOT NULL,
        day TEXT NOT NULL CHECK (day GLOB \(dayPattern)),
        -- `상태:횟수|기록할 때의 습관 내용`. 나중에 버전이 도착해도 지난 기록이 바뀌지 않게 한 필드로 고정한다.
        outcome TEXT NOT NULL CHECK (
            outcome GLOB 'empty:[0-9]*' OR outcome GLOB 'done:[0-9]*'
            OR outcome GLOB 'rest:[0-9]*' OR outcome GLOB 'skipped:[0-9]*'
        ),
        memo TEXT,
        UNIQUE (routine_id, day)
    ) STRICT;
    CREATE INDEX routine_record_day ON routine_record (day);

    CREATE TABLE routine_group (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        cue TEXT,
        color TEXT,
        sort_order REAL NOT NULL DEFAULT 0,
        deleted_at INTEGER
    ) STRICT;

    CREATE TABLE mode (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        deleted_at INTEGER
    ) STRICT;

    CREATE TABLE mode_schedule (
        day TEXT PRIMARY KEY CHECK (day GLOB \(dayPattern)),
        mode_id TEXT NOT NULL
    ) STRICT;

    CREATE TABLE focus_session (
        id TEXT PRIMARY KEY,
        owner_type TEXT CHECK (owner_type IS NULL OR owner_type IN ('task', 'routine')),
        owner_id TEXT,
        start_at INTEGER NOT NULL,
        end_at INTEGER,
        paused_seconds INTEGER NOT NULL DEFAULT 0 CHECK (paused_seconds >= 0),
        note TEXT,
        deleted_at INTEGER
    ) STRICT;

    CREATE TABLE day_note (
        day TEXT PRIMARY KEY CHECK (day GLOB \(dayPattern)),
        text TEXT NOT NULL
    ) STRICT;

    CREATE TABLE sort_order (
        context TEXT NOT NULL,
        item_type TEXT NOT NULL,
        item_id TEXT NOT NULL,
        position REAL NOT NULL,
        PRIMARY KEY (context, item_type, item_id)
    ) STRICT;
    """
}
