-- Migration: Create GitHub Credentials Storage Tables
-- Version: 1.0.0
-- Purpose: Store encrypted GitHub OAuth tokens and connection metadata

-- Main table for storing GitHub credentials per tenant
CREATE TABLE TenantGitHubCredentials (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    TenantId UNIQUEIDENTIFIER NOT NULL UNIQUE,
    EncryptedAccessToken NVARCHAR(MAX) NOT NULL,
    TokenType NVARCHAR(50) NOT NULL DEFAULT 'Bearer', -- 'Bearer' for OAuth, 'Token' for PAT
    GitHubUsername NVARCHAR(255) NOT NULL,
    GitHubUserId INT NOT NULL,
    GitHubUserEmail NVARCHAR(255),

    -- Metadata for management
    ConnectedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    LastVerifiedAt DATETIMEOFFSET,
    LastUsedAt DATETIMEOFFSET,
    IsActive BIT NOT NULL DEFAULT 1,
    DisconnectedAt DATETIMEOFFSET,
    DisconnectReason NVARCHAR(500),

    -- Audit fields
    CreatedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    CreatedBy NVARCHAR(255) NOT NULL,
    UpdatedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    UpdatedBy NVARCHAR(255) NOT NULL,

    CONSTRAINT CK_TenantGitHubCredentials_TokenType
        CHECK (TokenType IN ('Bearer', 'Token')),
    CONSTRAINT CK_TenantGitHubCredentials_Active
        CHECK ((IsActive = 1 AND DisconnectedAt IS NULL) OR (IsActive = 0 AND DisconnectedAt IS NOT NULL))
);

CREATE INDEX IX_TenantGitHubCredentials_TenantId
    ON TenantGitHubCredentials(TenantId);

CREATE INDEX IX_TenantGitHubCredentials_GitHubUsername
    ON TenantGitHubCredentials(GitHubUsername);

CREATE INDEX IX_TenantGitHubCredentials_Active
    ON TenantGitHubCredentials(IsActive)
    INCLUDE (TenantId, GitHubUsername);

-- Scope metadata for GitHub permissions
CREATE TABLE TenantGitHubScopes (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    TenantGitHubCredentialsId UNIQUEIDENTIFIER NOT NULL,
    ScopeName NVARCHAR(100) NOT NULL, -- 'repo', 'gist', 'user', etc.
    GrantedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),

    CONSTRAINT FK_TenantGitHubScopes_Credentials
        FOREIGN KEY (TenantGitHubCredentialsId)
        REFERENCES TenantGitHubCredentials(Id) ON DELETE CASCADE,
    CONSTRAINT UQ_TenantGitHubScopes_Unique
        UNIQUE (TenantGitHubCredentialsId, ScopeName)
);

CREATE INDEX IX_TenantGitHubScopes_CredentialsId
    ON TenantGitHubScopes(TenantGitHubCredentialsId);

-- Track failed verification attempts for security monitoring
CREATE TABLE GitHubConnectionFailures (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    TenantId UNIQUEIDENTIFIER NOT NULL,
    FailureType NVARCHAR(50) NOT NULL, -- 'TokenExpired', 'InvalidToken', 'RateLimited', 'NetworkError', etc.
    ErrorMessage NVARCHAR(MAX),
    FailedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    ResolvedAt DATETIMEOFFSET,
    IsResolved BIT NOT NULL DEFAULT 0,

    CONSTRAINT FK_GitHubConnectionFailures_Tenant
        FOREIGN KEY (TenantId)
        REFERENCES Tenants(Id) ON DELETE CASCADE
);

CREATE INDEX IX_GitHubConnectionFailures_TenantId
    ON GitHubConnectionFailures(TenantId);

CREATE INDEX IX_GitHubConnectionFailures_FailedAt
    ON GitHubConnectionFailures(FailedAt)
    INCLUDE (TenantId, FailureType);

-- OAuth session tracking for security
CREATE TABLE GitHubOAuthSessions (
    Id UNIQUEIDENTIFIER PRIMARY KEY NOT NULL DEFAULT (NEWID()),
    TenantId UNIQUEIDENTIFIER NOT NULL,
    State NVARCHAR(255) NOT NULL UNIQUE, -- CSRF protection state parameter
    CodeChallenge NVARCHAR(255), -- PKCE code challenge
    CreatedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    ExpiresAt DATETIMEOFFSET NOT NULL,
    CompletedAt DATETIMEOFFSET,
    IsCompleted BIT NOT NULL DEFAULT 0,

    CONSTRAINT FK_GitHubOAuthSessions_Tenant
        FOREIGN KEY (TenantId)
        REFERENCES Tenants(Id) ON DELETE CASCADE,
    CONSTRAINT CK_GitHubOAuthSessions_Expiry
        CHECK (ExpiresAt > CreatedAt)
);

CREATE INDEX IX_GitHubOAuthSessions_State
    ON GitHubOAuthSessions(State);

CREATE INDEX IX_GitHubOAuthSessions_TenantId
    ON GitHubOAuthSessions(TenantId, IsCompleted);

CREATE INDEX IX_GitHubOAuthSessions_ExpiresAt
    ON GitHubOAuthSessions(ExpiresAt)
    WHERE IsCompleted = 0;
