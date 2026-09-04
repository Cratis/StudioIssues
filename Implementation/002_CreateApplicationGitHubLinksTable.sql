-- Migration: Create Application GitHub Repository Links
-- Version: 1.0.0
-- Purpose: Track which Studio Applications are linked to GitHub repositories

-- Links Applications to GitHub repositories
CREATE TABLE ApplicationGitHubRepositoryLinks (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    ApplicationId UNIQUEIDENTIFIER NOT NULL,
    TenantId UNIQUEIDENTIFIER NOT NULL,
    GitHubRepositoryOwner NVARCHAR(255) NOT NULL,
    GitHubRepositoryName NVARCHAR(255) NOT NULL,
    GitHubRepositoryFullName NVARCHAR(510) NOT NULL, -- "owner/repo" format
    GitHubRepositoryId INT NOT NULL, -- GitHub's numeric repository ID
    DefaultBranch NVARCHAR(255) NOT NULL DEFAULT 'main',

    -- Sync configuration
    SyncEnabled BIT NOT NULL DEFAULT 1,
    SyncStrategy NVARCHAR(50) NOT NULL DEFAULT 'Manual', -- 'Manual', 'OnCommit', 'Scheduled'
    LastSyncAt DATETIMEOFFSET,
    LastSyncStatus NVARCHAR(50), -- 'Success', 'Failed', 'PartialSuccess', 'Pending'
    LastSyncErrorMessage NVARCHAR(MAX),
    FilesLastSyncedCount INT,

    -- Audit fields
    LinkedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    LinkedBy NVARCHAR(255) NOT NULL,
    UnlinkedAt DATETIMEOFFSET,
    UnlinkedBy NVARCHAR(255),
    CreatedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    UpdatedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),

    CONSTRAINT FK_AppGitHubLinks_Application
        FOREIGN KEY (ApplicationId)
        REFERENCES Applications(Id) ON DELETE CASCADE,
    CONSTRAINT FK_AppGitHubLinks_Tenant
        FOREIGN KEY (TenantId)
        REFERENCES Tenants(Id) ON DELETE CASCADE,
    CONSTRAINT UQ_AppGitHubLink_AppAndRepo
        UNIQUE (ApplicationId, GitHubRepositoryFullName),
    CONSTRAINT CK_AppGitHubLinks_SyncStrategy
        CHECK (SyncStrategy IN ('Manual', 'OnCommit', 'Scheduled')),
    CONSTRAINT CK_AppGitHubLinks_LinkedUnlinked
        CHECK ((UnlinkedAt IS NULL AND UnlinkedBy IS NULL) OR (UnlinkedAt IS NOT NULL AND UnlinkedBy IS NOT NULL))
);

CREATE INDEX IX_AppGitHubLinks_ApplicationId
    ON ApplicationGitHubRepositoryLinks(ApplicationId);

CREATE INDEX IX_AppGitHubLinks_TenantId
    ON ApplicationGitHubRepositoryLinks(TenantId);

CREATE INDEX IX_AppGitHubLinks_Repository
    ON ApplicationGitHubRepositoryLinks(GitHubRepositoryOwner, GitHubRepositoryName);

CREATE INDEX IX_AppGitHubLinks_SyncStatus
    ON ApplicationGitHubRepositoryLinks(SyncEnabled, LastSyncStatus)
    INCLUDE (ApplicationId, LastSyncAt);

-- Track file mappings between repository and local filesystem
CREATE TABLE GitHubRepositoryFileMappings (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    ApplicationGitHubRepositoryLinkId UNIQUEIDENTIFIER NOT NULL,
    GitHubFilePath NVARCHAR(MAX) NOT NULL, -- Path in GitHub repo
    LocalFilePath NVARCHAR(MAX) NOT NULL, -- Relative path in application folder
    GitHubSHA NVARCHAR(40), -- Git SHA of the file
    SyncedAt DATETIMEOFFSET,

    CONSTRAINT FK_FileMapping_RepositoryLink
        FOREIGN KEY (ApplicationGitHubRepositoryLinkId)
        REFERENCES ApplicationGitHubRepositoryLinks(Id) ON DELETE CASCADE
);

CREATE INDEX IX_GitHubRepositoryFileMappings_RepositoryLinkId
    ON GitHubRepositoryFileMappings(ApplicationGitHubRepositoryLinkId);

CREATE INDEX IX_GitHubRepositoryFileMappings_GitHubPath
    ON GitHubRepositoryFileMappings(GitHubFilePath);

-- Track sync history for audit and debugging
CREATE TABLE ApplicationGitHubSyncHistory (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    ApplicationGitHubRepositoryLinkId UNIQUEIDENTIFIER NOT NULL,
    SyncStartedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    SyncCompletedAt DATETIMEOFFSET,
    Status NVARCHAR(50) NOT NULL, -- 'InProgress', 'Success', 'Failed', 'PartialSuccess'
    FilesProcessed INT,
    FilesCreated INT,
    FilesUpdated INT,
    FilesDeleted INT,
    FilesSkipped INT,
    ErrorMessage NVARCHAR(MAX),
    SyncedBy NVARCHAR(255), -- User who initiated sync
    SyncTrigger NVARCHAR(50) NOT NULL DEFAULT 'Manual', -- 'Manual', 'Scheduled', 'Webhook'

    CONSTRAINT FK_SyncHistory_RepositoryLink
        FOREIGN KEY (ApplicationGitHubRepositoryLinkId)
        REFERENCES ApplicationGitHubRepositoryLinks(Id) ON DELETE CASCADE,
    CONSTRAINT CK_SyncHistory_Status
        CHECK (Status IN ('InProgress', 'Success', 'Failed', 'PartialSuccess')),
    CONSTRAINT CK_SyncHistory_Completed
        CHECK ((Status = 'InProgress' AND SyncCompletedAt IS NULL) OR (Status != 'InProgress' AND SyncCompletedAt IS NOT NULL))
);

CREATE INDEX IX_SyncHistory_RepositoryLinkId
    ON ApplicationGitHubSyncHistory(ApplicationGitHubRepositoryLinkId);

CREATE INDEX IX_SyncHistory_Status
    ON ApplicationGitHubSyncHistory(Status, SyncStartedAt DESC);

CREATE INDEX IX_SyncHistory_StartTime
    ON ApplicationGitHubSyncHistory(SyncStartedAt DESC)
    INCLUDE (Status);

-- GitHub webhook registrations
CREATE TABLE GitHubWebhookRegistrations (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    ApplicationGitHubRepositoryLinkId UNIQUEIDENTIFIER NOT NULL,
    GitHubWebhookId INT NOT NULL, -- GitHub's webhook ID
    Secret NVARCHAR(255) NOT NULL, -- HMAC secret for webhook verification
    Events NVARCHAR(MAX) NOT NULL, -- JSON array of subscribed events
    IsActive BIT NOT NULL DEFAULT 1,
    CreatedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    LastPingAt DATETIMEOFFSET,

    CONSTRAINT FK_Webhook_RepositoryLink
        FOREIGN KEY (ApplicationGitHubRepositoryLinkId)
        REFERENCES ApplicationGitHubRepositoryLinks(Id) ON DELETE CASCADE,
    CONSTRAINT UQ_Webhook_GitHubId
        UNIQUE (GitHubWebhookId)
);

CREATE INDEX IX_GitHubWebhookRegistrations_RepositoryLinkId
    ON GitHubWebhookRegistrations(ApplicationGitHubRepositoryLinkId);

CREATE INDEX IX_GitHubWebhookRegistrations_Active
    ON GitHubWebhookRegistrations(IsActive);

-- Track webhook deliveries for debugging
CREATE TABLE GitHubWebhookDeliveries (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    GitHubWebhookRegistrationId UNIQUEIDENTIFIER NOT NULL,
    GitHubDeliveryId NVARCHAR(50) NOT NULL, -- GitHub's delivery ID
    EventType NVARCHAR(50) NOT NULL, -- 'push', 'pull_request', etc.
    Payload NVARCHAR(MAX) NOT NULL, -- Raw JSON payload
    ProcessedAt DATETIMEOFFSET,
    ProcessingStatus NVARCHAR(50) NOT NULL DEFAULT 'Pending', -- 'Pending', 'Processing', 'Success', 'Failed'
    ProcessingError NVARCHAR(MAX),

    CONSTRAINT FK_WebhookDelivery_Registration
        FOREIGN KEY (GitHubWebhookRegistrationId)
        REFERENCES GitHubWebhookRegistrations(Id) ON DELETE CASCADE,
    CONSTRAINT UQ_WebhookDelivery_GitHubId
        UNIQUE (GitHubDeliveryId)
);

CREATE INDEX IX_GitHubWebhookDeliveries_RegistrationId
    ON GitHubWebhookDeliveries(GitHubWebhookRegistrationId);

CREATE INDEX IX_GitHubWebhookDeliveries_Status
    ON GitHubWebhookDeliveries(ProcessingStatus);

CREATE INDEX IX_GitHubWebhookDeliveries_EventType
    ON GitHubWebhookDeliveries(EventType)
    INCLUDE (ProcessingStatus);
