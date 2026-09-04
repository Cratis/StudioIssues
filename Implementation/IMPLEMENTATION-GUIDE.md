# GitHub & Filesystem Implementation Guide

**Issue**: Cratis/StudioIssues#311 - Make GitHub / Filesystem work  
**Target Repository**: Private Studio codebase  
**Status**: Architecture and specifications defined  

---

## Quick Start

This guide describes how to implement GitHub and Filesystem integration for Studio. The implementation is organized into phases that can be executed sequentially, each producing a buildable, testable increment.

### Prerequisites

- Cratis Arc CQRS framework knowledge
- Chronicle event sourcing patterns
- SQL Server or PostgreSQL experience
- GitHub API familiarity
- C# 13 and async/await patterns

### Key Files

1. **github-filesystem-architecture.md** — Complete architectural design
2. **001_CreateGitHubCredentialsTables.sql** — GitHub credentials storage
3. **002_CreateApplicationGitHubLinksTable.sql** — Repository link management
4. **003_CreateAuditLoggingTables.sql** — Security audit trails
5. **004_CreateIndexes.sql** — Performance optimization

---

## Phase 1: Filesystem Abstraction (Days 1-2)

### Objective
Create a type-safe, validated interface for all filesystem operations that enforces tenant isolation and sandbox restrictions.

### Key Components

#### 1.1 Path Management Types

Create `Features/FilesystemAccess/PathResolution.cs`:

```csharp
public record TenantStoragePath(string BaseStorage, TenantId TenantId)
{
    public string GetProjectPath(ProjectId projectId) =>
        Path.Combine(BaseStorage, TenantId.Value.ToString(), "projects", projectId.Value.ToString());

    public string GetApplicationPath(ProjectId projectId, ApplicationId applicationId) =>
        Path.Combine(GetProjectPath(projectId), "applications", applicationId.Value.ToString());

    public string ResolveFilePath(ProjectId projectId, ApplicationId applicationId, string relativePath)
    {
        var appRoot = GetApplicationPath(projectId, applicationId);
        var fullPath = Path.GetFullPath(Path.Combine(appRoot, relativePath));
        
        if (!fullPath.StartsWith(appRoot, StringComparison.Ordinal))
            throw new SandboxViolationException($"Path traversal detected: {relativePath}");
        
        return fullPath;
    }
}
```

#### 1.2 Filesystem Provider Interface

Create `Features/FilesystemAccess/IFilesystemProvider.cs`:

```csharp
public interface IFilesystemProvider
{
    Task<string> ReadFileAsync(TenantId tenantId, ProjectId projectId, ApplicationId applicationId, string relativePath);
    Task WriteFileAsync(TenantId tenantId, ProjectId projectId, ApplicationId applicationId, string relativePath, string content);
    Task<IEnumerable<FileInfo>> ListFilesAsync(TenantId tenantId, ProjectId projectId, ApplicationId applicationId, string relativePath = "");
    Task DeleteFileAsync(TenantId tenantId, ProjectId projectId, ApplicationId applicationId, string relativePath);
    Task EnsureDirectoryAsync(TenantId tenantId, ProjectId projectId, ApplicationId applicationId, string relativePath);
}
```

#### 1.3 Sandbox Validator

Create `Features/FilesystemAccess/SandboxValidator.cs`:

```csharp
public class SandboxValidator
{
    private const int MaxDepth = 10;
    private static readonly string[] ReservedNames = { ".git", ".hg", ".svn", "node_modules" };

    public void ValidatePath(string relativePath, string applicationRoot)
    {
        // Implementation as shown in architecture
    }
}
```

#### 1.4 Physical Implementation

Create `Features/FilesystemAccess/FileSystemProvider.cs`:

```csharp
public class FileSystemProvider(
    string baseStoragePath,
    SandboxValidator validator,
    IFilesystemOperationAuditLog auditLog) : IFilesystemProvider
{
    public async Task<string> ReadFileAsync(TenantId tenantId, ProjectId projectId, 
        ApplicationId applicationId, string relativePath)
    {
        var pathManager = new TenantStoragePath(baseStoragePath, tenantId);
        var fullPath = pathManager.ResolveFilePath(projectId, applicationId, relativePath);
        
        validator.ValidatePath(relativePath, pathManager.GetApplicationPath(projectId, applicationId));
        
        try
        {
            var content = await File.ReadAllTextAsync(fullPath);
            await auditLog.LogOperationAsync(tenantId, applicationId, "Read", relativePath, "File", success: true);
            return content;
        }
        catch (Exception ex)
        {
            await auditLog.LogOperationAsync(tenantId, applicationId, "Read", relativePath, "File", 
                success: false, errorMessage: ex.Message);
            throw;
        }
    }

    // Implement other interface methods following same pattern
}
```

### Testing Strategy

**Unit Tests** (`when_resolving_paths/`):
- Validate path traversal prevention
- Test symlink detection
- Verify depth limit enforcement
- Check reserved name blocking

**Integration Tests** (`when_reading_files/`, `when_writing_files/`):
- Full read/write cycle
- Multi-tenant isolation (read file from Tenant A, verify Tenant B cannot access)
- Audit logging verification

### Success Criteria

- ✅ Path resolution works for all scopes
- ✅ Sandbox violations throw appropriate exceptions
- ✅ Multi-tenant isolation verified in tests
- ✅ `dotnet build` succeeds with zero warnings

---

## Phase 2: Tenant Isolation (Day 3)

### Objective
Implement middleware and context management to automatically scope all requests to tenant context.

### Key Components

#### 2.1 Tenant Context

Create `Features/TenantIsolation/ITenantContext.cs`:

```csharp
public interface ITenantContext
{
    TenantId TenantId { get; }
    UserId CurrentUserId { get; }
    DateTime OperationTime { get; }
}

public class TenantContext : ITenantContext
{
    public TenantId TenantId { get; init; }
    public UserId CurrentUserId { get; init; }
    public DateTime OperationTime { get; init; }
}
```

#### 2.2 Middleware

Create `Features/TenantIsolation/TenantScopingMiddleware.cs`:

```csharp
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

    private TenantId? ExtractTenantId(HttpContext context) =>
        context.User?.FindFirst("tenant_id")?.Value as TenantId;
}
```

#### 2.3 Database Query Scoping

Update all queries to automatically filter by tenant:

```csharp
public class TenantScopedDbContext : DbContext
{
    private readonly ITenantContext _tenantContext;

    public override int SaveChanges()
    {
        foreach (var entry in ChangeTracker.Entries())
        {
            if (entry.Entity is ITenantScoped tenantScoped)
                tenantScoped.TenantId = _tenantContext.TenantId;
        }
        return base.SaveChanges();
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        foreach (var entityType in modelBuilder.Model.GetEntityTypes())
        {
            if (typeof(ITenantScoped).IsAssignableFrom(entityType.ClrType))
            {
                modelBuilder.Entity(entityType.ClrType)
                    .HasQueryFilter(e => EF.Property<TenantId>(e, "TenantId") == _tenantContext.TenantId);
            }
        }
        base.OnModelCreating(modelBuilder);
    }
}
```

### Testing Strategy

**Unit Tests**:
- Middleware extracts tenant correctly
- Context providers return correct scope
- Query filters applied automatically

**Integration Tests**:
- Multi-tenant requests don't leak data
- Each tenant can only see own data

### Success Criteria

- ✅ Tenant context flows through all requests
- ✅ Database queries automatically scoped
- ✅ No cross-tenant data leakage

---

## Phase 3: GitHub Credential Storage (Day 4)

### Objective
Implement encrypted storage for GitHub tokens and connection metadata.

### Key Components

#### 3.1 Database Setup

Run migrations in order:
```sql
-- In your migration runner
1. 001_CreateGitHubCredentialsTables.sql
2. 003_CreateAuditLoggingTables.sql -- for audit events
4. 004_CreateIndexes.sql
```

#### 3.2 Credential Encryption

Create `Features/GitHubIntegration/CredentialEncryption.cs`:

```csharp
public class CredentialEncryption
{
    private readonly IDataProtectionProvider _protectionProvider;

    public string EncryptToken(string accessToken)
    {
        var protector = _protectionProvider.CreateProtector("GitHub.AccessToken");
        return protector.Protect(accessToken);
    }

    public string DecryptToken(string encryptedToken)
    {
        var protector = _protectionProvider.CreateProtector("GitHub.AccessToken");
        return protector.Unprotect(encryptedToken);
    }
}
```

#### 3.3 Credential Storage

Create `Features/GitHubIntegration/GitHubCredentialsStorage.cs`:

```csharp
public class GitHubCredentialsStorage(DbContext context, CredentialEncryption encryption)
{
    public async Task StoreAsync(TenantId tenantId, string accessToken, string gitHubUsername, int gitHubUserId)
    {
        var encrypted = encryption.EncryptToken(accessToken);
        
        var credentials = new TenantGitHubCredentials
        {
            TenantId = tenantId,
            EncryptedAccessToken = encrypted,
            GitHubUsername = gitHubUsername,
            GitHubUserId = gitHubUserId,
            IsActive = true
        };

        context.Add(credentials);
        await context.SaveChangesAsync();
    }

    public async Task<string> GetTokenAsync(TenantId tenantId)
    {
        var credentials = await context.TenantGitHubCredentials
            .Where(c => c.TenantId == tenantId && c.IsActive)
            .FirstOrDefaultAsync();

        if (credentials == null)
            throw new GitHubNotConnectedException(tenantId);

        return encryption.DecryptToken(credentials.EncryptedAccessToken);
    }
}
```

### Testing Strategy

**Unit Tests**:
- Encryption/decryption cycle
- Token rotation
- Credential deletion

**Integration Tests**:
- Store and retrieve encrypted tokens
- Multi-tenant isolation

### Success Criteria

- ✅ Tokens stored encrypted
- ✅ Tokens never logged
- ✅ Tokens retrievable and functional

---

## Phase 4: GitHub OAuth Integration (Days 5-6)

### Objective
Implement GitHub OAuth flow for secure authentication.

### Key Components

#### 4.1 OAuth Configuration

Update `appsettings.json`:

```json
{
  "GitHub": {
    "ClientId": "your-github-app-id",
    "ClientSecret": "vault:github-client-secret",
    "CallbackUrl": "https://studio.example.com/github/callback",
    "ApiBaseUrl": "https://api.github.com"
  }
}
```

#### 4.2 GitHub Service

Create `Features/GitHubIntegration/GitHubService.cs`:

```csharp
public class GitHubService(
    HttpClient httpClient,
    GitHubCredentialsStorage credentialsStorage,
    IConfiguration config) : IGitHubService
{
    public async Task<string> GetAuthorizationUrlAsync(TenantId tenantId)
    {
        var clientId = config["GitHub:ClientId"];
        var state = GenerateSecureState(tenantId);
        await _oauthSessionStore.SaveStateAsync(tenantId, state);

        return $"https://github.com/login/oauth/authorize?" +
               $"client_id={clientId}&" +
               $"redirect_uri={Uri.EscapeDataString(config["GitHub:CallbackUrl"])}&" +
               $"scope=repo&" +
               $"state={state}";
    }

    public async Task<GitHubConnectionResult> ExchangeAuthorizationCodeAsync(
        TenantId tenantId, string code)
    {
        // Exchange code for access token
        var tokenResponse = await _tokenExchanger.ExchangeAsync(code);
        
        // Validate token and get user info
        var user = await GetCurrentUserAsync(tenantId, tokenResponse.AccessToken);
        
        // Store credentials
        await credentialsStorage.StoreAsync(tenantId, tokenResponse.AccessToken, 
            user.Login, user.Id);

        return new GitHubConnectionResult(user.Login, user.Email);
    }

    public async Task<GitHubUser> GetCurrentUserAsync(TenantId tenantId)
    {
        var token = await credentialsStorage.GetTokenAsync(tenantId);
        return await GetCurrentUserAsync(tenantId, token);
    }

    private async Task<GitHubUser> GetCurrentUserAsync(TenantId tenantId, string accessToken)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "https://api.github.com/user");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Headers.UserAgent.ParseAdd("Studio");

        var response = await httpClient.SendAsync(request);
        response.EnsureSuccessStatusCode();

        var content = await response.Content.ReadAsStringAsync();
        return JsonSerializer.Deserialize<GitHubUser>(content)!;
    }

    public async Task<IEnumerable<GitHubRepository>> ListRepositoriesAsync(TenantId tenantId)
    {
        var token = await credentialsStorage.GetTokenAsync(tenantId);
        
        var request = new HttpRequestMessage(HttpMethod.Get, 
            "https://api.github.com/user/repos?per_page=100");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.UserAgent.ParseAdd("Studio");

        var response = await httpClient.SendAsync(request);
        response.EnsureSuccessStatusCode();

        var content = await response.Content.ReadAsStringAsync();
        return JsonSerializer.Deserialize<List<GitHubRepository>>(content)!;
    }
}
```

#### 4.3 OAuth Controller

Create `Features/GitHubIntegration/GitHubOAuthController.cs`:

```csharp
[ApiController]
[Route("api/github")]
public class GitHubOAuthController(IGitHubService githubService)
{
    [HttpPost("connect")]
    public async Task<IActionResult> StartConnection([FromBody] ConnectGitHubRequest request)
    {
        var url = await githubService.GetAuthorizationUrlAsync(request.TenantId);
        return Ok(new { authorizationUrl = url });
    }

    [HttpGet("callback")]
    public async Task<IActionResult> Callback([FromQuery] string code, [FromQuery] string state)
    {
        var tenantId = await _oauthSessionStore.GetTenantIdAsync(state);
        var result = await githubService.ExchangeAuthorizationCodeAsync(tenantId, code);
        
        return Redirect($"/settings/github?connected=true&username={result.GitHubUsername}");
    }

    [HttpPost("disconnect")]
    public async Task<IActionResult> Disconnect([FromBody] DisconnectGitHubRequest request)
    {
        await githubService.DisconnectAsync(request.TenantId);
        return Ok();
    }
}
```

### Testing Strategy

**Unit Tests**:
- OAuth URL generation
- Token exchange logic
- User profile parsing

**Integration Tests**:
- Full OAuth flow (with GitHub sandbox app)
- Token storage and retrieval
- Connection verification

### Success Criteria

- ✅ OAuth flow complete
- ✅ Tokens stored securely
- ✅ Connection verified with GitHub

---

## Phase 5: Agent Sandbox (Day 7)

### Objective
Implement agent-specific filesystem access restrictions.

### Key Components

#### 5.1 Agent Filesystem Provider

Create `Features/AgentSandbox/IAgentFilesystemProvider.cs`:

```csharp
public interface IAgentFilesystemProvider
{
    Task<string> ReadFileAsync(string relativePath);
    Task WriteFileAsync(string relativePath, string content);
    Task<IEnumerable<FileInfo>> ListFilesAsync(string relativePath = "");
}
```

#### 5.2 Sandboxed Implementation

Create `Features/AgentSandbox/SandboxedAgentFilesystemProvider.cs`:

```csharp
public class SandboxedAgentFilesystemProvider(
    IFilesystemProvider provider,
    TenantId tenantId,
    ProjectId projectId,
    ApplicationId applicationId,
    IAgentAccessAuditLog auditLog) : IAgentFilesystemProvider
{
    public async Task<string> ReadFileAsync(string relativePath)
    {
        await auditLog.LogAccessAsync(tenantId, applicationId, "Agent", "Read", 
            relativePath, allowed: true);
        
        return await provider.ReadFileAsync(tenantId, projectId, applicationId, relativePath);
    }

    public async Task WriteFileAsync(string relativePath, string content)
    {
        // Restrict write permissions if needed
        if (IsRestrictedPath(relativePath))
        {
            await auditLog.LogAccessAsync(tenantId, applicationId, "Agent", "Write", 
                relativePath, allowed: false, denyReason: "Restricted path");
            throw new SandboxViolationException($"Cannot write to {relativePath}");
        }

        await auditLog.LogAccessAsync(tenantId, applicationId, "Agent", "Write", 
            relativePath, allowed: true);
        
        await provider.WriteFileAsync(tenantId, projectId, applicationId, relativePath, content);
    }

    private bool IsRestrictedPath(string relativePath) =>
        relativePath.Contains(".git") ||
        relativePath.Contains(".env") ||
        relativePath.Contains("secrets");
}
```

### Testing Strategy

**Unit Tests**:
- Restricted path detection
- Access logging

**Integration Tests**:
- Agent read/write operations
- Violation detection and logging

### Success Criteria

- ✅ Agent filesystem operations logged
- ✅ Restricted paths blocked
- ✅ Violations recorded

---

## Phase 6: UI & Commands (Days 8-9)

### Objective
Create user interface and Arc commands for GitHub management.

### Key Components

#### 6.1 Commands

Create `Features/GitHubIntegration/ConnectGitHubAccount.cs`:

```csharp
[Command]
public record ConnectGitHubAccount(
    TenantId TenantId,
    string AuthorizationCode)
{
    public async Task<Result<GitHubConnectionResult>> Handle(
        IGitHubService githubService,
        IEventLog eventLog)
    {
        try
        {
            var result = await githubService.ExchangeAuthorizationCodeAsync(
                TenantId, AuthorizationCode);

            var @event = new GitHubAccountConnected(
                TenantId,
                result.GitHubUsername,
                DateTimeOffset.UtcNow);

            await eventLog.AppendAsync(TenantId, @event);

            return Result<GitHubConnectionResult>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<GitHubConnectionResult>.Failed(ex.Message);
        }
    }
}
```

#### 6.2 React Component

Create `Features/GitHubIntegration/ConnectGitHub.tsx`:

```tsx
export const ConnectGitHub = () => {
    const [state, setState] = useState<'idle' | 'connecting' | 'connected'>('idle');
    const { useCommand } = useCommandProxy();

    const handleConnect = async () => {
        setState('connecting');
        try {
            const { authorizationUrl } = await fetch('/api/github/connect', {
                method: 'POST',
                body: JSON.stringify({ tenantId: currentTenant.id })
            }).then(r => r.json());

            window.location.href = authorizationUrl;
        } catch (error) {
            setState('idle');
        }
    };

    return (
        <div>
            <h2>Connect to GitHub</h2>
            <Button 
                onClick={handleConnect}
                disabled={state !== 'idle'}
                loading={state === 'connecting'}
            >
                Connect GitHub Account
            </Button>
        </div>
    );
};
```

### Testing Strategy

**Unit Tests**:
- Command validation
- Result handling

**Integration Specs**:
- Full command flow through Arc
- Event emission and storage

### Success Criteria

- ✅ Commands execute successfully
- ✅ UI displays properly
- ✅ Integration specs pass

---

## Phase 7: Testing & Documentation (Days 10-11)

### Objective
Comprehensive testing and documentation of all features.

### Key Components

#### 7.1 Integration Specs

Create comprehensive specs following Cratis patterns:

```csharp
// Features/GitHubIntegration/when_connecting_github/and_authorization_succeeds.cs
public class and_authorization_succeeds : Specification
{
    private ConnectGitHubCommand _command;
    private EventLog _eventLog;
    private GitHubAccountConnected _event;

    void Establish()
    {
        _command = new ConnectGitHubCommand(TenantId.New(), "valid_code");
        _eventLog = new MockEventLog();
    }

    void Because()
    {
        var result = _command.Handle(_eventLog).Result;
        _result = result;
    }

    [Fact]
    void should_return_success() => _result.IsSuccess.ShouldBeTrue();
    
    [Fact]
    void should_emit_github_account_connected_event() =>
        _eventLog.Events.OfType<GitHubAccountConnected>().ShouldContainOnly(_event);
}
```

#### 7.2 Documentation

Create comprehensive guides:

- **API Documentation** — All endpoints with examples
- **Admin Guide** — Setup and configuration
- **User Guide** — How to connect GitHub and manage repositories
- **Security Guide** — How isolation and sandboxing work

### Testing Strategy

- Unit test coverage: >80%
- Integration specs for all commands
- Security test scenarios
- Load testing for audit tables

### Success Criteria

- ✅ All tests green
- ✅ Zero build warnings
- ✅ Documentation complete
- ✅ Security review passed

---

## Deployment Checklist

Before deploying to production:

### Pre-Deployment

- [ ] All tests pass in staging environment
- [ ] Database migrations validated
- [ ] GitHub OAuth app configured
- [ ] Filesystem storage paths created
- [ ] Encryption keys generated and stored securely
- [ ] Audit log retention policies set
- [ ] Monitoring and alerting configured

### Deployment Steps

```bash
# 1. Run database migrations
dotnet run --project Infrastructure.Migrations

# 2. Verify filesystem setup
- Check /BaseStorage created with correct permissions
- Verify tenant folders created for existing tenants
- Test read/write permissions

# 3. Verify GitHub OAuth
- Test connection flow in staging
- Verify tokens stored encrypted
- Test token refresh

# 4. Verify agent sandbox
- Run agent with restricted filesystem
- Verify audit logs generated
- Test violation detection

# 5. Run smoke tests
- Create new tenant
- Connect GitHub
- Link repository
- Generate code
```

### Post-Deployment

- [ ] Monitor audit logs for violations
- [ ] Monitor GitHub API rate limits
- [ ] Verify storage capacity
- [ ] Check backup completion
- [ ] Validate tenant isolation

---

## References

### Cratis Resources

- **Chronicle**: Event sourcing patterns — See event design rules
- **Arc**: CQRS framework — Commands, events, validators
- **Vertical Slices**: Code organization — Keep feature complete in one folder

### Security Resources

- **OWASP**: Path traversal, authentication, access control
- **GitHub**: OAuth best practices, API rate limiting
- **Microsoft**: DPAPI for credential encryption

### Related Issues

- StudioIssues#311 — This implementation
- Review Stagehand GitHub integration for reference patterns
- Check Stagehand filesystem access for sandbox patterns

---

## Common Issues & Solutions

### "Path Traversal Detected"
- Ensure paths use `/` not `\`
- Verify `Path.GetFullPath()` is called
- Check path is within application boundary

### GitHub Token Expired
- Implement refresh token flow
- Monitor `GitHubConnectionFailures` table
- Alert administrator for action

### Sandbox Violation Alerts
- Check for legitimate use cases
- Review `SandboxViolationLog` for patterns
- Consider whitelisting if legitimate

### Audit Table Growth
- Implement retention policies
- Archive old records monthly
- Monitor query performance

---

## Support

For implementation questions:
1. Review this guide thoroughly
2. Check the architecture document
3. Study Cratis patterns in Chronicle and Arc
4. Reference Stagehand implementations

Last Updated: 2026-09-04  
Status: Ready for implementation
