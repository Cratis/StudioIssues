# GitHub & Filesystem Integration Implementation

**Issue**: [Cratis/StudioIssues#311 — Make GitHub / Filesystem work](https://github.com/Cratis/StudioIssues/issues/311)

This directory contains comprehensive architecture and implementation documentation for adding GitHub and Filesystem integration to Studio.

## Overview

The feature enables Studio to:
- Provide a shared filesystem for code generation across all instances
- Enforce strict per-tenant isolation with hierarchical scoping
- Sandbox agent access to prevent unauthorized filesystem operations
- Integrate with GitHub for repository management
- Maintain comprehensive audit trails for security compliance

## Directory Contents

### Architecture & Design

**`github-filesystem-architecture.md`** — Complete architectural specification
- Overview and core requirements
- Detailed component architecture
- Security considerations
- Database schema design
- API endpoint specifications
- Implementation phases (7 phases, 10-11 days estimated)
- Configuration and testing strategy

### Implementation Guide

**`IMPLEMENTATION-GUIDE.md`** — Step-by-step implementation instructions
- Prerequisites and setup
- Detailed phase-by-phase breakdown
- Code examples for each component
- Testing strategy for each phase
- Deployment checklist
- Common issues and solutions
- Success criteria for each phase

### Database Migrations

**`001_CreateGitHubCredentialsTables.sql`**
- `TenantGitHubCredentials` — Encrypted GitHub tokens per tenant
- `TenantGitHubScopes` — OAuth scope tracking
- `GitHubConnectionFailures` — Connection monitoring
- `GitHubOAuthSessions` — OAuth session state tracking

**`002_CreateApplicationGitHubLinksTable.sql`**
- `ApplicationGitHubRepositoryLinks` — Application-to-repository mappings
- `GitHubRepositoryFileMappings` — File sync tracking
- `ApplicationGitHubSyncHistory` — Sync audit trail
- `GitHubWebhookRegistrations` — Webhook management
- `GitHubWebhookDeliveries` — Webhook event tracking

**`003_CreateAuditLoggingTables.sql`**
- `FilesystemOperationAuditLog` — All filesystem operations
- `SandboxViolationLog` — Security violation tracking
- `GitHubApiCallLog` — GitHub API call audit trail
- `AgentAccessAuditLog` — Agent filesystem access tracking
- `AuditLogStatistics` — Aggregated metrics

**`004_CreateIndexes.sql`**
- Performance indexes for all tables
- Covering indexes for common queries
- Statistics for query optimization
- Includes filtered indexes for common conditions

## Quick Start

### For Implementation Teams

1. **Read the Architecture**
   ```bash
   # Start with the main architecture document
   cat github-filesystem-architecture.md
   ```

2. **Follow the Implementation Guide**
   ```bash
   # Phase-by-phase instructions with code examples
   cat IMPLEMENTATION-GUIDE.md
   ```

3. **Apply Database Migrations**
   ```bash
   # Run in order
   sqlcmd -i 001_CreateGitHubCredentialsTables.sql
   sqlcmd -i 002_CreateApplicationGitHubLinksTable.sql
   sqlcmd -i 003_CreateAuditLoggingTables.sql
   sqlcmd -i 004_CreateIndexes.sql
   ```

4. **Implement by Phase**
   - Each phase is designed to be independently completable
   - Phases should be done sequentially for proper dependencies
   - Each phase produces a buildable, testable increment

### For Reviewers

1. **Understand the Architecture**
   - Review the architecture document for design decisions
   - Check security considerations for compliance
   - Verify component boundaries align with your system

2. **Validate Database Design**
   - Review SQL schema for normalization and integrity
   - Check indexes for query performance
   - Verify audit tables for compliance requirements

3. **Review Implementation Details**
   - Check code examples in implementation guide
   - Verify they follow Cratis Arc patterns
   - Ensure security patterns are correctly applied

## Architecture Highlights

### Hierarchical Filesystem Scoping

```
/BaseStorage/
├── {TenantId}/
│   └── projects/
│       └── {ProjectId}/
│           └── applications/
│               └── {ApplicationId}/      ← Agent sandbox boundary
│                   ├── src/
│                   ├── generated/
│                   └── config/
```

### Security Defense-in-Depth

1. **Tenant Isolation** — Middleware enforces tenant context on all requests
2. **Path Validation** — Prevent `../` traversal, symlink escape, depth attacks
3. **Agent Sandboxing** — Additional restrictions for agent filesystem access
4. **Audit Logging** — Complete record of all operations for compliance
5. **Encrypted Credentials** — GitHub tokens encrypted at rest using DPAPI

### Key Technologies

- **Chronicle** — Event sourcing for state changes
- **Arc** — CQRS framework for commands and projections
- **Entity Framework Core** — Database access and migrations
- **GitHub OAuth 2.0** — Secure authentication
- **SQL Server / PostgreSQL** — Persistent storage

## Implementation Timeline

- **Phase 1: Filesystem Abstraction** (Days 1-2)
- **Phase 2: Tenant Isolation** (Day 3)
- **Phase 3: GitHub Credential Storage** (Day 4)
- **Phase 4: GitHub OAuth Integration** (Days 5-6)
- **Phase 5: Agent Sandbox Restrictions** (Day 7)
- **Phase 6: UI & Commands** (Days 8-9)
- **Phase 7: Testing & Documentation** (Days 10-11)

**Estimated Total**: 10-11 developer days

## Key Design Decisions

### 1. Interface-Based Filesystem Access
**Decision**: All filesystem operations go through `IFilesystemProvider` interface  
**Why**: Enables testing, mocking, and future multi-storage backends (S3, Azure, etc.)

### 2. Encrypted Token Storage
**Decision**: GitHub tokens encrypted at rest, never logged  
**Why**: Compliance with GitHub security best practices and PCI-DSS requirements

### 3. Event-Sourced State Changes
**Decision**: All significant operations (connect, disconnect, sync) emit events  
**Why**: Audit trail, replay capability, and temporal queries using Chronicle

### 4. Separate Audit Tables
**Decision**: Audit logging in dedicated tables separate from operational data  
**Why**: Audit logs are immutable, high-volume, and have different retention policies

### 5. Hierarchical Scoping
**Decision**: Tenant → Project → Application with agent sandbox at application level  
**Why**: Aligns with Studio's data model and provides proper isolation boundaries

## Security Considerations

### Threat Model

| Threat | Mitigation |
|--------|-----------|
| Path traversal to escape sandbox | Path validation, canonical resolution, boundary checks |
| Symlink escape | Symlink detection and rejection |
| Cross-tenant access | Tenant context middleware, query scoping, DB constraints |
| Token exposure | Encryption at rest, never logged, HTTPS in flight |
| Agent escape | Sandboxed provider wrapper with additional validation |
| DOS via recursion | Depth limit (10 levels), folder count limit |
| GitHub API abuse | Rate limit monitoring, token rotation, audit logging |

### Compliance

- **Audit Trail**: All operations logged with user, timestamp, outcome
- **Data Isolation**: Per-tenant filesystem and database scoping
- **Encryption**: Credentials encrypted at rest using DPAPI
- **Access Control**: Tenant context enforced on all requests
- **Retention**: Configurable audit log retention policies

## Database Schema Relationships

```
Tenants
    ↓
TenantGitHubCredentials
    ├── TenantGitHubScopes
    ├── GitHubConnectionFailures
    └── GitHubOAuthSessions

Applications
    ↓
ApplicationGitHubRepositoryLinks
    ├── GitHubRepositoryFileMappings
    ├── ApplicationGitHubSyncHistory
    ├── GitHubWebhookRegistrations
    │   └── GitHubWebhookDeliveries
    └── (audit logs reference ApplicationId)

AuditLogs
    ├── FilesystemOperationAuditLog
    ├── SandboxViolationLog
    ├── GitHubApiCallLog
    ├── AgentAccessAuditLog
    └── AuditLogStatistics
```

## Testing Strategy

### Unit Tests
- Path validation and sandbox violations
- Token encryption/decryption
- GitHub API response parsing
- Audit log formatting

### Integration Tests
- Full OAuth flow with GitHub sandbox app
- Multi-tenant isolation verification
- Filesystem operations with audit trail
- Agent sandbox enforcement

### Security Tests
- Path traversal attempts
- Symlink escape attempts
- Cross-tenant access attempts
- Token exposure scenarios
- Agent sandbox breakout attempts

### Load Tests
- Audit table query performance with millions of records
- Concurrent filesystem operations
- GitHub API rate limit handling
- Webhook delivery processing

## Deployment Considerations

### Pre-Deployment
- GitHub OAuth app created and configured
- Filesystem storage paths prepared
- Encryption keys generated and stored securely
- Audit log retention policies configured
- Monitoring and alerting set up

### Database Migrations
- Run migrations in order (001 → 004)
- Validate schema in staging environment
- Plan for audit table growth (100K+ records/day per tenant)
- Configure backup policies

### Rollback Plan
- Maintain separate GitHub OAuth app instance for easy deactivation
- Keep audit logs immutable and separate from operational data
- Design agents to gracefully handle missing filesystem provider
- Have manual sync procedure as fallback

## Monitoring & Operations

### Key Metrics

1. **Filesystem Operations**
   - Operations/sec by type (read, write, delete)
   - Operation latency p50/p95/p99
   - Failed operations rate

2. **GitHub Integration**
   - OAuth connection success rate
   - API call success rate
   - Rate limit violations
   - Webhook delivery latency

3. **Security**
   - Sandbox violations per tenant
   - Failed sandbox violation attempts
   - Audit log ingestion rate
   - Storage capacity utilization

### Alerting

- Alert on sandbox violation spike
- Alert on GitHub API rate limit warnings
- Alert on audit table growth anomalies
- Alert on cross-tenant access attempts (should be 0)

## References & Links

### Cratis Projects
- [Chronicle](https://github.com/Cratis/Chronicle) — Event sourcing
- [Arc](https://github.com/Cratis/Arc) — CQRS framework
- [Screenplay](https://github.com/Cratis/Screenplay) — Event model DSL
- [Studio](https://cratis.studio) — Live application

### GitHub API
- [GitHub OAuth Documentation](https://docs.github.com/en/developers/apps/building-oauth-apps)
- [GitHub REST API](https://docs.github.com/en/rest)
- [GitHub App Best Practices](https://docs.github.com/en/developers/apps/best-practices-for-creating-a-github-app)

### Related Issues

- **StudioIssues#311** — This feature
- Check [Stagehand](https://github.com/Cratis/Stagehand) for reference implementations of GitHub integration and filesystem access patterns

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| Architecture | ✅ Complete | Comprehensive design documented |
| Database Schema | ✅ Complete | 4 migration scripts ready |
| Implementation Guide | ✅ Complete | Phase-by-phase instructions with examples |
| Code Examples | ✅ Included | In implementation guide, ready to adapt |
| Testing Strategy | ✅ Included | Unit, integration, security, and load tests defined |
| Documentation | ✅ Complete | Architecture, implementation, and deployment guides |

**Last Updated**: 2026-09-04  
**Prepared For**: Private Studio Repository Implementation Team  
**Status**: Ready for implementation

---

## Support & Questions

For questions during implementation:

1. **Architecture Questions** → Review `github-filesystem-architecture.md`
2. **Implementation Questions** → Review `IMPLEMENTATION-GUIDE.md` and code examples
3. **Database Questions** → Review SQL migration scripts and schema diagrams
4. **Security Questions** → Check "Security Considerations" section above
5. **Cratis Patterns** → Reference Chronicle and Arc documentation
6. **GitHub Integration** → Check GitHub API documentation links above

---

*This documentation set was prepared as comprehensive guidance for implementing GitHub and Filesystem integration for Cratis Studio. It provides everything needed to build a secure, maintainable, multi-tenant system with proper audit trails and sandbox protections.*
