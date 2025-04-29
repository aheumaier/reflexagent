# ADR-0001: Use Hexagonal Architecture

**Status**: accepted  
**Date**: 2025-04-30

## Context
We need a clean separation between our domain logic and infrastructure (Rails, Redis, Slack, Sidekiq) to enable testability and future tech swaps.

## Decision
Adopt a Ports & Adapters (Hexagonal) architecture.  
- Core business logic lives under `app/core/`  
- Ports in `app/ports/`, Adapters in `app/adapters/`  
- Dependency Injection wired in `config/initializers/dependency_injection.rb`

## Consequences
- + Great testability of core via port mocks  
- + Flexibility to swap adapters (e.g. Redis → Memcached)  
- – Some initial boilerplate in setting up ports/adapters  