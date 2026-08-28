import SwiftData

/// Schema versioning policy
/// -------------------------
/// PrintKit uses SwiftData `VersionedSchema` + `SchemaMigrationPlan` from day one.
///
/// * V1 is the launch schema. Every persisted model is registered below.
/// * When the schema changes, create `SchemaV2` (keeping V1 frozen), add it to
///   `schemas`, and append a `MigrationStage` describing the transition.
/// * Identifiers are UUIDs everywhere; display names are never used as keys.
/// * No `.unique` attributes and no required relationships are used, so the
///   store remains compatible with enabling CloudKit synchronisation later.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Spool.self,
            DryingSession.self,
            StorageLocation.self,
            FilamentTransfer.self,
            DesiccantUnit.self,
            EnvironmentLog.self,
            WishlistItem.self,
            PurchaseRecord.self,
            PrinterDevice.self,
            NozzleRecord.self,
            BuildPlate.self,
            AccessoryItem.self,
            MaintenanceTask.self,
            MaintenanceLog.self,
            PrintRecord.self,
            ProjectItem.self,
            BOMItem.self,
            PrintQueueItem.self,
            FailureReport.self,
            SlicerProfile.self,
            CalibrationRecord.self,
            ToleranceEntry.self,
            FlowLimitRecord.self,
            MaterialOverride.self
        ]
    }
}

enum PrintKitMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    /// Empty at launch. Append stages here when SchemaV2+ is introduced.
    static var stages: [MigrationStage] {
        []
    }
}
