# GitHub & Filesystem Integration Architecture
## Issue: Cratis/StudioIssues#311

### Overview

This document describes the architecture and implementation approach for integrating GitHub and filesystem access into Studio. This feature enables code generation by providing:

1. A shared, multi-tenant filesystem for storing generated code
2. Strict per-tenant isolation with hierarchical scoping
3. Agent-level sandboxing to prevent unauthorized access
4. GitHub integration for code repository management

---

## Core Requirements

From issue #311, the implementation must satisfy:

1. **Shared Filesystem**: A file share available to all running Studio instances
2. **Tenant Isolation**: Strict per-tenant scope - agents can only access their tenant's data
3. **Hierarchical Structure**: `/BaseStorage/{TenantId}/projects/{ProjectId}/applications/{ApplicationId}`
4. **Agent Sandbox**: Agents cannot read or write outside their application folder
5. **GitHub Integration**: "Connect to GitHub" functionality with registration scripts
6. **Reference Pattern**: Follow Stagehand's implementation patterns for Git/GitHub and file access

---

## Architecture Overview

### Filesystem Structure

```
/BaseStorage/
├── {TenantId}/
│   ├── projects/
│   │   ├── {ProjectId}/
│   │   │   ├── applications/
│   │   │   │   ├── {ApplicationId}/
│   │   │   │   │   ├── src/
│   │   │   │   │   ├── generated/
│   │   │   │   │   └── config/
│   │   │   │   └── ...
│   │   │   └── ...
│   │   └── ...
│   └── ...
└── ...
```

Each application folder is the **sandbox boundary** for agent operations.

### Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        HTTP Layer                           │
│  (Controllers expose Connect GitHub, Manage Repos, etc.)    │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                    Command Layer (Arc)                      │
│  - ConnectGitHubAccount                                    │
│  - DisconnectGitHubAccount                                 │
│  - LinkApplicationToRepository                             │
│  - SyncRepositoryFiles                                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                  Service Layer                              │
│  ┌──────────────────┬────────────────┬────────────────┐    │
│  │  GitHub Service  │ Filesystem Svc │  Tenant Scoped │    │
│  │  - OAuth Flow    │  - Path Mgmt   │  - Isolation   │    │
│  │  - API Calls     │  - Validation  │  - Sandbox     │    │
│  │  - Credentials   │  - Sync Ops    │  - Audit Log   │    │
│  └──────────────────┴────────────────┴────────────────┘    │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│              Infrastructure Layer                           │
│  ┌────────────────┬──────────────┬──────────────────┐      │
│  │  DB Storage    │  Filesystem  │  GitHub API      │      │
│  │  - Credentials │  (Actual I/O) │  (External API) │      │
│  │  - Audit Log   │              │                  │      │
│  │  - Metadata    │              │                  │      │
│  └────────────────┴──────────────┴──────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

---

## Detailed Design

### 1. Filesystem Abstraction Layer

**Purpose**: Provide a type-safe, validated interface for all filesystem operations.

**IFilesystemProvider Interface** (abstract the physical filesystem):

```csharp
public interface IFilesystemProvider
{
    /// <summary>
    /// Gets the application-scoped root directory for the agent.
    /// </summary>
    Task<string> GetApplicationRootAsync(TenantId tenantId, ProjectId projectId, ApplicationId applicationId);

    /// <summary>
    /// Reads a file within the tenant's scope.
    /// Validates path to prevent traversal.
    /// </summary>
    Task<string> ReadFileAsync(TenantId tenantId, ProjectId projectId, ApplicationId applicationId, string relativePath);

    /// <summary>
    /// Writes a file within the tenant's scope.
    /// Creates directories as needed.
    /// </summary>
    Task WriteFileAsync(TenantId tenantId, ProjectId projectId, ApplicationId applicationId, string relativePath, string content);

    /// <summary>
    /// Lists files in a directory within the tenant's scope.
    /// </summary>
    Task<IEnumerable<FileInfo>> ListFilesAsync(TenantId tenantId, ProjectId projectId, ApplicationId applicationId, string relativePath = "");

    /// <summary>
    /// Deletes a file within the tenant's scope.
    /// </summary>
    Task DeleteFileAsync(TenantId tenantId, ProjectId projectId, ApplicationId applicationId, string relativePath);

    /// <summary>
    /// Ensures a directory exists within the tenant's scope.
    /// </summary>
    Task EnsureDirectoryAsync(TenantId tenantId, ProjectId projectId, ApplicationId applicationId, string relativePath);
}
```

**Key Operations**:
- Path resolution with tenant/project/application context
- Sandbox validation (prevent `../` traversal, symlinks, etc.)
- Recursive depth limit enforcement
- Audit logging of all operations

### 2. Sandbox Validation

**Validation Rules**:

1. **Path Traversal Prevention**: Reject paths containing `..` or absolute paths
2. **Symlink Blocking**: Reject symlink targets outside sandbox
3. **Recursive Depth Limit**: Max 10 levels deep to prevent DOS
4. **Reserved Names**: Prevent access to system folders
5. **Case Sensitivity**: Handle platform differences (Windows vs Linux)

**Implementation Pattern**:

```csharp
public class SandboxValidator
{
    private const int MaxDepth = 10;
    private static readonly string[] ReservedNames = { ".git", ".hg", ".svn", "node_modules" };

    public void ValidatePath(string relativePath, string applicationRoot)
    {
        // 1. Prevent absolute paths
        if (Path.IsPathRooted(relativePath))
            throw new SandboxViolationException("Absolute paths not allowed");

        // 2. Resolve to absolute and check within bounds
        var fullPath = Path.GetFullPath(Path.Combine(applicationRoot, relativePath));
        if (!fullPath.StartsWith(applicationRoot, StringComparison.Ordinal))
            throw new SandboxViolationException("Path traversal detected");

        // 3. Check depth
        var depth = fullPath.Count(c => c == Path.DirectorySeparatorChar);
        if (depth > MaxDepth)
            throw new SandboxViolationException("Depth limit exceeded");

        // 4. Check for symlinks (if supported by OS)
        var info = new FileInfo(fullPath);
        if (IsSymlink(info))
            throw new SandboxViolationException("Symlinks not allowed");

        // 5. Check reserved names in path
        var parts = relativePath.Split(Path.DirectorySeparatorChar);
        if (parts.Any(p => ReservedNames.Contains(p)))
            throw new SandboxViolationException("Reserved folder names not allowed");
    }

    private bool IsSymlink(FileInfo fileInfo)
    {
        // Implementation varies by OS
        // On Windows: check file attributes
        // On Linux: check if stat indicates symlink
        return (fileInfo.Attributes & FileAttributes.ReparsePoint) != 0;
    }
}
```

### 3. Tenant Isolation Middleware

**Purpose**: Automatically scope requests to tenant context.

**Tenant Context Capture**:

```csharp
public interface ITenantContext
{
    TenantId TenantId { get; }
    UserId CurrentUserId { get; }
    DateTime OperationTime { get; }
}

public class TenantScopingMiddleware
{
    public async Task InvokeAsync(HttpContext context, ITenantContextProvider provider)
    {
        var tenantId = ExtractTenantId(context);
        if (tenantId == null)
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }

        var tenantContext = await provider.GetTenantContextAsync(tenantId);
        context.Items["TenantContext"] = tenantContext;

        await _next(context);
    }

    private TenantId? ExtractTenantId(HttpContext context)
    {
        // Extract from: JWT token, header, or session
        return context.User?.FindFirst("tenant_id")?.Value as TenantId;
    }
}
```

### 4. GitHub Integration

**OAuth Flow**:

1. User clicks "Connect GitHub" in UI
2. System redirects to GitHub OAuth authorization endpoint
3. User authorizes Studio application on GitHub
4. GitHub redirects back with authorization code
5. Backend exchanges code for access token
6. Token is encrypted and stored in database (per-tenant)
7. System tests token by fetching user profile

**Supported Authentication Methods**:
- Personal Access Token (PAT) - User creates manually
- GitHub App OAuth flow - Studio-hosted app
- OAuth for GitHub Enterprise (future)

**IGitHubService Interface**:

```csharp
public interface IGitHubService
{
    /// <summary>
    /// Gets authorization URL for OAuth flow.
    /// </summary>
    Task<string> GetAuthorizationUrlAsync(TenantId tenantId);

    /// <summary>
    /// Exchanges authorization code for access token and stores it.
    /// </summary>
    Task<GitHubConnectionResult> ExchangeAuthorizationCodeAsync(TenantId tenantId, string code);

    /// <summary>
    /// Lists repositories accessible with current credentials.
    /// </summary>
    Task<IEnumerable<GitHubRepository>> ListRepositoriesAsync(TenantId tenantId);

    /// <summary>
    /// Fetches a file from a GitHub repository.
    /// </summary>
    Task<string> GetFileContentAsync(TenantId tenantId, string owner, string repo, string path);

    /// <summary>
    /// Gets the authenticated user's GitHub profile.
    /// </summary>
    Task<GitHubUser> GetCurrentUserAsync(TenantId tenantId);

    /// <summary>
    /// Disconnects GitHub account for the tenant.
    /// </summary>
    Task DisconnectAsync(TenantId tenantId);
}
```

### 5. Credential Storage

**Database Schema**:

```sql
CREATE TABLE TenantGitHubCredentials (
    Id GUID PRIMARY KEY,
    TenantId GUID NOT NULL UNIQUE,
    EncryptedAccessToken VARCHAR(MAX) NOT NULL,
    GitHubUsername VARCHAR(255) NOT NULL,
    ConnectedAt DATETIMEOFFSET NOT NULL,
    LastVerifiedAt DATETIMEOFFSET,
    IsActive BIT NOT NULL DEFAULT 1,
    
    CONSTRAINT FK_TenantGitHubCredentials_Tenant FOREIGN KEY (TenantId)
        REFERENCES Tenants(Id) ON DELETE CASCADE
);

CREATE TABLE ApplicationGitHubLinks (
    Id GUID PRIMARY KEY,
    ApplicationId GUID NOT NULL,
    GitHubRepository VARCHAR(255) NOT NULL, -- "owner/repo" format
    LinkedAt DATETIMEOFFSET NOT NULL,
    SyncEnabled BIT NOT NULL DEFAULT 1,
    
    CONSTRAINT FK_AppGitHubLinks_Application FOREIGN KEY (ApplicationId)
        REFERENCES Applications(Id) ON DELETE CASCADE,
    CONSTRAINT UQ_AppGitHubLink_RepoPerApp UNIQUE (ApplicationId, GitHubRepository)
);
```

**Encryption**:
- Use DPAPI or similar for at-rest encryption
- Never log or expose tokens
- Rotate tokens periodically
- Revoke immediately on disconnect

### 6. Agent Sandbox Implementation

**Agent Filesystem Provider** (wrapper around base provider):

```csharp
public interface IAgentFilesystemProvider
{
    /// <summary>
    /// Agent can only access its assigned application folder.
    /// No cross-application or cross-tenant access.
    /// </summary>
    Task<string> ReadFileAsync(string relativePath);
    Task WriteFileAsync(string relativePath, string content);
    Task<IEnumerable<FileInfo>> ListFilesAsync(string relativePath = "");
    Task DeleteFileAsync(string relativePath);
}

public class SandboxedAgentFilesystemProvider : IAgentFilesystemProvider
{
    private readonly IFilesystemProvider _provider;
    private readonly TenantId _tenantId;
    private readonly ProjectId _projectId;
    private readonly ApplicationId _applicationId;

    public async Task<string> ReadFileAsync(string relativePath)
    {
        // Additional agent-specific validation
        // - No write operations in sensitive folders
        // - Audit log all reads
        
        return await _provider.ReadFileAsync(_tenantId, _projectId, _applicationId, relativePath);
    }

    // ... other methods follow same pattern
}
```

### 7. Commands & Events (Arc CQRS Pattern)

**Commands**:

```csharp
[Command]
public record ConnectGitHubAccount(
    TenantId TenantId,
    string AuthorizationCode) { }

[Command]
public record DisconnectGitHubAccount(
    TenantId TenantId) { }

[Command]
public record LinkApplicationToRepository(
    ApplicationId ApplicationId,
    string RepositoryReference) { } // "owner/repo" format

[Command]
public record SyncRepositoryFiles(
    ApplicationId ApplicationId,
    string Branch = "main") { }
```

**Events**:

```csharp
[EventType]
public record GitHubAccountConnected(
    TenantId TenantId,
    string GitHubUsername,
    DateTimeOffset ConnectedAt);

[EventType]
public record GitHubAccountDisconnected(
    TenantId TenantId,
    DateTimeOffset DisconnectedAt);

[EventType]
public record ApplicationLinkedToGitHubRepository(
    ApplicationId ApplicationId,
    string RepositoryReference,
    DateTimeOffset LinkedAt);

[EventType]
public record RepositoryFilesSynced(
    ApplicationId ApplicationId,
    string Branch,
    int FilesUpdated,
    DateTimeOffset SyncTime);

[EventType]
public record SandboxViolationAttempted(
    TenantId TenantId,
    ApplicationId ApplicationId,
    string ViolationType,
    string Details,
    DateTimeOffset Timestamp);
```

**Read Models**:

```csharp
[ReadModel]
public record TenantGitHubConnection
{
    [Key]
    public TenantId TenantId { get; init; }

    public string GitHubUsername { get; init; }
    public bool IsConnected { get; init; }
    public DateTimeOffset? ConnectedAt { get; init; }
    public DateTimeOffset? LastVerifiedAt { get; init; }

    // Projection from events
    [FromEvent<GitHubAccountConnected>]
    public static TenantGitHubConnection WhenConnected(TenantGitHubConnection model, GitHubAccountConnected @event)
    {
        return model with
        {
            IsConnected = true,
            GitHubUsername = @event.GitHubUsername,
            ConnectedAt = @event.ConnectedAt
        };
    }
}

[ReadModel]
public record ApplicationRepository
{
    [Key]
    public ApplicationId ApplicationId { get; init; }

    public string RepositoryReference { get; init; }
    public bool IsSynced { get; init; }
    public DateTimeOffset? LastSyncTime { get; init; }
    public int FileCount { get; init; }

    // Projection from events
}
```

---

## Implementation Phases

### Phase 1: Core Filesystem Abstraction (Days 1-2)
- Implement `IFilesystemProvider` interface
- Create path resolution logic with tenant/project/app context
- Implement `SandboxValidator`
- Write comprehensive tests for sandbox violations

### Phase 2: Tenant Isolation (Day 3)
- Implement `ITenantContext` and middleware
- Add tenant-scoped database queries
- Create audit logging for filesystem operations
- Test multi-tenant isolation

### Phase 3: GitHub Credential Storage (Day 4)
- Design and create database schema
- Implement encrypted credential storage
- Create registration migration scripts
- Test credential encryption/decryption

### Phase 4: GitHub OAuth Integration (Days 5-6)
- Implement GitHub OAuth flow
- Create `IGitHubService` implementation
- Add token validation and refresh
- Write integration tests

### Phase 5: Agent Sandbox Restrictions (Day 7)
- Create `IAgentFilesystemProvider`
- Implement agent-specific access restrictions
- Add audit logging
- Test agent sandbox

### Phase 6: UI & Commands (Days 8-9)
- Create "Connect to GitHub" command and dialog
- Implement repository selection UI
- Create sync UI
- Wire up all Arc commands

### Phase 7: Testing & Documentation (Days 10-11)
- Write integration specs for all commands
- Document API endpoints
- Create admin guides
- Security review

---

## Security Considerations

### 1. Path Traversal
- **Threat**: Attacker uses `../` to escape tenant sandbox
- **Mitigation**: Strict path validation, resolve to canonical path, check boundaries

### 2. Symlink Attacks
- **Threat**: Symlink to files outside sandbox
- **Mitigation**: Detect and reject symlinks

### 3. Token Exposure
- **Threat**: GitHub token leaked or compromised
- **Mitigation**: Encrypt at rest, never log, short-lived tokens, revocation

### 4. Cross-Tenant Access
- **Threat**: Tenant accesses another tenant's data
- **Mitigation**: Tenant context validation on every request, database query scoping

### 5. Agent Escape
- **Threat**: Agent reads outside its application folder
- **Mitigation**: Additional validation layer, audit all operations

### 6. DOS via Recursion
- **Threat**: Agent creates deeply nested folders
- **Mitigation**: Max depth limit, folder count limit

### 7. Credential Interception
- **Threat**: Token intercepted during OAuth flow
- **Mitigation**: HTTPS only, PKCE for OAuth, secure cookie flags

---

## Configuration

### Required Settings

```json
{
  "Filesystem": {
    "BaseStoragePath": "/var/studio/storage",
    "MaxFileSizeBytes": 10485760,
    "MaxPathDepth": 10,
    "EnforceSymlinkCheck": true
  },
  "GitHub": {
    "ClientId": "your-github-app-id",
    "ClientSecret": "vault:github-client-secret",
    "CallbackUrl": "https://studio.example.com/github/callback",
    "ApiBaseUrl": "https://api.github.com"
  },
  "Security": {
    "EncryptionKey": "vault:encryption-key",
    "AuditLogging": true,
    "TokenRotationDays": 90
  }
}
```

### Environment-Specific

- **Development**: Local filesystem, GitHub sandbox app
- **Staging**: Shared network storage, GitHub staging app  
- **Production**: Enterprise storage, GitHub production app with Enterprise Cloud support

---

## Database Migrations

See `registration-scripts/` directory for:
1. `001_CreateGitHubCredentialsTables.sql`
2. `002_CreateApplicationGitHubLinksTable.sql`
3. `003_AddAuditLoggingTables.sql`
4. `004_CreateIndexes.sql`

---

## API Endpoints

### Authentication

```http
POST /api/github/connect
GET  /api/github/callback?code=...&state=...
POST /api/github/disconnect
```

### Repository Management

```http
GET  /api/github/repositories
POST /api/applications/{applicationId}/link-github
DELETE /api/applications/{applicationId}/github
POST /api/applications/{applicationId}/sync-github
```

### File Operations

```http
GET  /api/applications/{applicationId}/files?path=...
POST /api/applications/{applicationId}/files
PUT  /api/applications/{applicationId}/files/{path}
DELETE /api/applications/{applicationId}/files/{path}
```

---

## Testing Strategy

### Unit Tests
- Path validation logic
- Sandbox violations
- Token encryption
- GitHub API mocking

### Integration Tests  
- Full OAuth flow (with GitHub sandbox)
- Multi-tenant isolation
- Credential storage and retrieval
- File operations through all layers

### Security Tests
- Path traversal attempts
- Symlink escape attempts  
- Cross-tenant access attempts
- Credential exposure scenarios
- Agent sandbox breakout attempts

---

## References

- **Stagehand Git/GitHub Implementation**: Examine for OAuth patterns, token management
- **Stagehand Filesystem Access**: Examine for sandbox implementation
- **Chronicle Event Sourcing**: Events for all state changes
- **Arc CQRS Framework**: Commands, handlers, validators
- **Cratis Vertical Slice Architecture**: Component organization

---

## Status

**Last Updated**: 2026-09-04  
**Prepared For**: StudioIssues #311  
**Target Repositories**: Private Studio codebase  

This architecture document serves as the specification for implementing GitHub and Filesystem integration in Studio. Follow the implementation phases sequentially and ensure all security considerations are addressed.
