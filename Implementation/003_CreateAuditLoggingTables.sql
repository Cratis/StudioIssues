-- Migration: Create Audit Logging Tables for Security
-- Version: 1.0.0
-- Purpose: Track all filesystem operations and security events for audit and compliance

-- Main audit log for all filesystem operations
CREATE TABLE FilesystemOperationAuditLog (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    TenantId UNIQUEIDENTIFIER NOT NULL,
    ApplicationId UNIQUEIDENTIFIER NOT NULL,
    OperationType NVARCHAR(50) NOT NULL, -- 'Read', 'Write', 'Delete', 'List', 'CreateDirectory'
    ResourcePath NVARCHAR(MAX) NOT NULL, -- Relative path within application sandbox
    ResourceType NVARCHAR(50) NOT NULL, -- 'File', 'Directory'
    Success BIT NOT NULL DEFAULT 1,
    ErrorMessage NVARCHAR(MAX),
    OperationInitiatedBy NVARCHAR(255) NOT NULL, -- User ID or 'System' or Agent ID
    OperationSource NVARCHAR(50) NOT NULL, -- 'HttpRequest', 'Agent', 'System', 'Webhook'
    RequestId NVARCHAR(255), -- Correlation ID for tracing
    ClientIpAddress NVARCHAR(45), -- IPv4 or IPv6
    UserAgent NVARCHAR(MAX),
    OperationTime DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),

    CONSTRAINT FK_AuditLog_Tenant
        FOREIGN KEY (TenantId)
        REFERENCES Tenants(Id) ON DELETE CASCADE,
    CONSTRAINT FK_AuditLog_Application
        FOREIGN KEY (ApplicationId)
        REFERENCES Applications(Id) ON DELETE CASCADE,
    CONSTRAINT CK_AuditLog_OperationType
        CHECK (OperationType IN ('Read', 'Write', 'Delete', 'List', 'CreateDirectory')),
    CONSTRAINT CK_AuditLog_ResourceType
        CHECK (ResourceType IN ('File', 'Directory')),
    CONSTRAINT CK_AuditLog_OperationSource
        CHECK (OperationSource IN ('HttpRequest', 'Agent', 'System', 'Webhook'))
);

CREATE INDEX IX_FilesystemOperationAuditLog_TenantId
    ON FilesystemOperationAuditLog(TenantId);

CREATE INDEX IX_FilesystemOperationAuditLog_ApplicationId
    ON FilesystemOperationAuditLog(ApplicationId);

CREATE INDEX IX_FilesystemOperationAuditLog_OperationTime
    ON FilesystemOperationAuditLog(OperationTime DESC)
    INCLUDE (TenantId, ApplicationId, OperationType);

CREATE INDEX IX_FilesystemOperationAuditLog_ResourcePath
    ON FilesystemOperationAuditLog(ResourcePath);

CREATE INDEX IX_FilesystemOperationAuditLog_InitiatedBy
    ON FilesystemOperationAuditLog(OperationInitiatedBy)
    INCLUDE (OperationTime, Success);

-- Sandbox violation attempts and security events
CREATE TABLE SandboxViolationLog (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    TenantId UNIQUEIDENTIFIER NOT NULL,
    ApplicationId UNIQUEIDENTIFIER NOT NULL,
    ViolationType NVARCHAR(50) NOT NULL, -- 'PathTraversal', 'SymlinkEscape', 'DepthLimitExceeded', 'ReservedNameAccess', 'UnauthorizedAccess'
    AttemptedPath NVARCHAR(MAX) NOT NULL,
    SandboxBoundary NVARCHAR(MAX) NOT NULL, -- The expected boundary that was violated
    AttemptedBy NVARCHAR(255) NOT NULL, -- User or Agent ID
    RequestId NVARCHAR(255),
    ClientIpAddress NVARCHAR(45),
    Details NVARCHAR(MAX), -- Additional context
    Severity NVARCHAR(50) NOT NULL DEFAULT 'Warning', -- 'Info', 'Warning', 'Critical'
    DetectedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    ResolutionStatus NVARCHAR(50) NOT NULL DEFAULT 'Pending', -- 'Pending', 'Reviewed', 'Resolved', 'FalsePositive'
    ReviewedBy NVARCHAR(255),
    ReviewedAt DATETIMEOFFSET,
    ReviewNotes NVARCHAR(MAX),

    CONSTRAINT FK_SandboxViolationLog_Tenant
        FOREIGN KEY (TenantId)
        REFERENCES Tenants(Id) ON DELETE CASCADE,
    CONSTRAINT FK_SandboxViolationLog_Application
        FOREIGN KEY (ApplicationId)
        REFERENCES Applications(Id) ON DELETE CASCADE,
    CONSTRAINT CK_SandboxViolation_Type
        CHECK (ViolationType IN ('PathTraversal', 'SymlinkEscape', 'DepthLimitExceeded', 'ReservedNameAccess', 'UnauthorizedAccess')),
    CONSTRAINT CK_SandboxViolation_Severity
        CHECK (Severity IN ('Info', 'Warning', 'Critical')),
    CONSTRAINT CK_SandboxViolation_ResolutionStatus
        CHECK (ResolutionStatus IN ('Pending', 'Reviewed', 'Resolved', 'FalsePositive'))
);

CREATE INDEX IX_SandboxViolationLog_TenantId
    ON SandboxViolationLog(TenantId);

CREATE INDEX IX_SandboxViolationLog_ApplicationId
    ON SandboxViolationLog(ApplicationId);

CREATE INDEX IX_SandboxViolationLog_DetectedAt
    ON SandboxViolationLog(DetectedAt DESC);

CREATE INDEX IX_SandboxViolationLog_ViolationType
    ON SandboxViolationLog(ViolationType)
    INCLUDE (DetectedAt, Severity);

CREATE INDEX IX_SandboxViolationLog_ResolutionStatus
    ON SandboxViolationLog(ResolutionStatus)
    WHERE ResolutionStatus != 'Resolved';

-- GitHub API call audit trail
CREATE TABLE GitHubApiCallLog (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    TenantId UNIQUEIDENTIFIER NOT NULL,
    ApiEndpoint NVARCHAR(MAX) NOT NULL,
    HttpMethod NVARCHAR(10) NOT NULL, -- 'GET', 'POST', 'PUT', 'DELETE', 'PATCH'
    RequestPayload NVARCHAR(MAX),
    ResponseStatusCode INT,
    ResponsePayload NVARCHAR(MAX),
    RateLimitRemaining INT,
    RateLimitResetAt DATETIMEOFFSET,
    ExecutionTimeMs INT,
    Success BIT NOT NULL DEFAULT 1,
    ErrorMessage NVARCHAR(MAX),
    CalledBy NVARCHAR(255) NOT NULL, -- User ID or System process
    CalledAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    RequestId NVARCHAR(255),

    CONSTRAINT FK_GitHubApiCallLog_Tenant
        FOREIGN KEY (TenantId)
        REFERENCES Tenants(Id) ON DELETE CASCADE,
    CONSTRAINT CK_GitHubApiCallLog_HttpMethod
        CHECK (HttpMethod IN ('GET', 'POST', 'PUT', 'DELETE', 'PATCH'))
);

CREATE INDEX IX_GitHubApiCallLog_TenantId
    ON GitHubApiCallLog(TenantId);

CREATE INDEX IX_GitHubApiCallLog_CalledAt
    ON GitHubApiCallLog(CalledAt DESC)
    INCLUDE (TenantId, Success);

CREATE INDEX IX_GitHubApiCallLog_Success
    ON GitHubApiCallLog(Success)
    WHERE Success = 0;

-- Agent access audit trail
CREATE TABLE AgentAccessAuditLog (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    TenantId UNIQUEIDENTIFIER NOT NULL,
    ApplicationId UNIQUEIDENTIFIER NOT NULL,
    AgentId NVARCHAR(255) NOT NULL,
    AccessType NVARCHAR(50) NOT NULL, -- 'Read', 'Write', 'Execute'
    ResourcePath NVARCHAR(MAX) NOT NULL,
    Allowed BIT NOT NULL DEFAULT 1,
    DenyReason NVARCHAR(255),
    AccessTime DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    Duration MS INT,

    CONSTRAINT FK_AgentAccessAuditLog_Tenant
        FOREIGN KEY (TenantId)
        REFERENCES Tenants(Id) ON DELETE CASCADE,
    CONSTRAINT FK_AgentAccessAuditLog_Application
        FOREIGN KEY (ApplicationId)
        REFERENCES Applications(Id) ON DELETE CASCADE,
    CONSTRAINT CK_AgentAccess_Type
        CHECK (AccessType IN ('Read', 'Write', 'Execute'))
);

CREATE INDEX IX_AgentAccessAuditLog_TenantId
    ON AgentAccessAuditLog(TenantId);

CREATE INDEX IX_AgentAccessAuditLog_ApplicationId
    ON AgentAccessAuditLog(ApplicationId);

CREATE INDEX IX_AgentAccessAuditLog_AgentId
    ON AgentAccessAuditLog(AgentId);

CREATE INDEX IX_AgentAccessAuditLog_AccessTime
    ON AgentAccessAuditLog(AccessTime DESC)
    INCLUDE (Allowed);

CREATE INDEX IX_AgentAccessAuditLog_Denied
    ON AgentAccessAuditLog(Allowed)
    WHERE Allowed = 0;

-- Aggregated statistics for monitoring
CREATE TABLE AuditLogStatistics (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    TenantId UNIQUEIDENTIFIER NOT NULL,
    StatisticDate DATE NOT NULL,
    FilesystemOperations INT DEFAULT 0,
    FailedOperations INT DEFAULT 0,
    SandboxViolations INT DEFAULT 0,
    GitHubApiCalls INT DEFAULT 0,
    FailedGitHubCalls INT DEFAULT 0,
    AgentAccess INT DEFAULT 0,
    DeniedAgentAccess INT DEFAULT 0,
    LastUpdatedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),

    CONSTRAINT FK_AuditLogStatistics_Tenant
        FOREIGN KEY (TenantId)
        REFERENCES Tenants(Id) ON DELETE CASCADE,
    CONSTRAINT UQ_AuditLogStatistics_TenantDate
        UNIQUE (TenantId, StatisticDate)
);

CREATE INDEX IX_AuditLogStatistics_StatisticDate
    ON AuditLogStatistics(StatisticDate DESC);

CREATE INDEX IX_AuditLogStatistics_TenantId
    ON AuditLogStatistics(TenantId);
