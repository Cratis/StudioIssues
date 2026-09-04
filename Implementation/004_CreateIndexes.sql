-- Migration: Create Performance Indexes
-- Version: 1.0.0
-- Purpose: Optimize common queries on GitHub and Filesystem tables

-- Optimize queries for tenant GitHub access verification
CREATE INDEX IX_TenantGitHubCredentials_ActiveByTenant
    ON TenantGitHubCredentials(TenantId)
    WHERE IsActive = 1
    INCLUDE (GitHubUsername, GitHubUserId, LastVerifiedAt);

-- Optimize queries for repository sync status
CREATE INDEX IX_ApplicationGitHubRepositoryLinks_BySyncStatus
    ON ApplicationGitHubRepositoryLinks(SyncEnabled, LastSyncStatus)
    WHERE UnlinkedAt IS NULL
    INCLUDE (ApplicationId, DefaultBranch, LastSyncAt);

-- Optimize queries for finding applications by GitHub repository
CREATE INDEX IX_ApplicationGitHubRepositoryLinks_ByRepository
    ON ApplicationGitHubRepositoryLinks(GitHubRepositoryOwner, GitHubRepositoryName)
    INCLUDE (ApplicationId, TenantId, SyncEnabled);

-- Optimize audit queries by date range and tenant
CREATE INDEX IX_FilesystemOperationAuditLog_ByTenantAndDate
    ON FilesystemOperationAuditLog(TenantId, OperationTime DESC)
    INCLUDE (ApplicationId, OperationType, Success);

-- Optimize queries for finding failed operations
CREATE INDEX IX_FilesystemOperationAuditLog_FailedOperations
    ON FilesystemOperationAuditLog(Success, OperationTime DESC)
    WHERE Success = 0
    INCLUDE (TenantId, ApplicationId, ErrorMessage);

-- Optimize sandbox violation queries
CREATE INDEX IX_SandboxViolationLog_ByTenantAndSeverity
    ON SandboxViolationLog(TenantId, Severity, DetectedAt DESC)
    INCLUDE (ViolationType, ApplicationId, AttemptedBy);

-- Optimize unresolved violation queries
CREATE INDEX IX_SandboxViolationLog_Unresolved
    ON SandboxViolationLog(ResolutionStatus, DetectedAt DESC)
    WHERE ResolutionStatus IN ('Pending', 'Reviewed')
    INCLUDE (TenantId, ApplicationId, Severity);

-- Optimize GitHub API call queries
CREATE INDEX IX_GitHubApiCallLog_ByTenantAndSuccess
    ON GitHubApiCallLog(TenantId, Success, CalledAt DESC)
    INCLUDE (ApiEndpoint, ResponseStatusCode, ExecutionTimeMs);

-- Optimize rate limit monitoring queries
CREATE INDEX IX_GitHubApiCallLog_RateLimitTracking
    ON GitHubApiCallLog(TenantId, CalledAt DESC)
    WHERE RateLimitRemaining IS NOT NULL
    INCLUDE (RateLimitRemaining, RateLimitResetAt);

-- Optimize agent access audit queries
CREATE INDEX IX_AgentAccessAuditLog_ByAgentAndApplication
    ON AgentAccessAuditLog(ApplicationId, AgentId, AccessTime DESC)
    INCLUDE (AccessType, Allowed, DenyReason);

-- Optimize denied agent access queries
CREATE INDEX IX_AgentAccessAuditLog_DeniedAccess
    ON AgentAccessAuditLog(Allowed, AccessTime DESC)
    WHERE Allowed = 0
    INCLUDE (TenantId, ApplicationId, AgentId, DenyReason);

-- Optimize sync history queries
CREATE INDEX IX_ApplicationGitHubSyncHistory_ByRepositoryAndStatus
    ON ApplicationGitHubSyncHistory(ApplicationGitHubRepositoryLinkId, Status)
    INCLUDE (SyncStartedAt, FilesProcessed, FilesCreated, FilesUpdated);

-- Optimize recent sync queries
CREATE INDEX IX_ApplicationGitHubSyncHistory_RecentSync
    ON ApplicationGitHubSyncHistory(SyncStartedAt DESC)
    INCLUDE (ApplicationGitHubRepositoryLinkId, Status, FilesProcessed);

-- Optimize webhook delivery queries
CREATE INDEX IX_GitHubWebhookDeliveries_ByRegistrationAndStatus
    ON GitHubWebhookDeliveries(GitHubWebhookRegistrationId, ProcessingStatus)
    INCLUDE (EventType, ProcessedAt);

-- Optimize unprocessed webhook queries
CREATE INDEX IX_GitHubWebhookDeliveries_Pending
    ON GitHubWebhookDeliveries(ProcessingStatus)
    WHERE ProcessingStatus IN ('Pending', 'Processing')
    INCLUDE (GitHubWebhookRegistrationId, EventType);

-- Optimize scope queries
CREATE INDEX IX_TenantGitHubScopes_ByCredentials
    ON TenantGitHubScopes(TenantGitHubCredentialsId)
    INCLUDE (ScopeName, GrantedAt);

-- Optimize OAuth session queries
CREATE INDEX IX_GitHubOAuthSessions_Active
    ON GitHubOAuthSessions(ExpiresAt)
    WHERE IsCompleted = 0;

-- Optimize connection failure tracking
CREATE INDEX IX_GitHubConnectionFailures_ByTenantAndResolution
    ON GitHubConnectionFailures(TenantId, IsResolved, FailedAt DESC)
    INCLUDE (FailureType, ErrorMessage);

-- Statistics index hints for query optimizer
-- These provide the query optimizer with information about common access patterns
-- They help maintain up-to-date statistics for optimal query plans

-- Ensure statistics are current after bulk operations
CREATE STATISTICS stats_TenantGitHubCredentials_Active
    ON TenantGitHubCredentials(TenantId, IsActive);

CREATE STATISTICS stats_ApplicationGitHubLinks_Sync
    ON ApplicationGitHubRepositoryLinks(SyncEnabled, LastSyncStatus);

CREATE STATISTICS stats_FilesystemAuditLog_Success
    ON FilesystemOperationAuditLog(TenantId, Success);

CREATE STATISTICS stats_SandboxViolation_Severity
    ON SandboxViolationLog(Severity, DetectedAt);

CREATE STATISTICS stats_GitHubApiCall_Success
    ON GitHubApiCallLog(TenantId, Success);

CREATE STATISTICS stats_AgentAccess_Allowed
    ON AgentAccessAuditLog(ApplicationId, Allowed);
