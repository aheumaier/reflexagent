---
title: ADR-0003: Metrics Filtering Approach
status: proposed
date: 2024-07-10
---

# ADR-0003: Metrics Filtering Approach

**Status**: proposed  
**Date**: 2024-07-10

## Context

We need to enhance our metric analysis capabilities by providing filtering functionality (e.g., by time period, author, repository) for commit metrics (github.push.XXX). In our hexagonal architecture, we must decide where this filtering logic should be implemented:

1. **Service Layer**: Enhancing the metrics service to handle filtering
2. **Controller Layer**: Adding filtering logic in controllers
3. **Core Layer**: Adding filtering to core use cases

Currently, our filtering implementation is mixed:
- The `MetricsService` has a `filter_dimensions` parameter in methods like `top_metrics` and `aggregate`
- Controllers construct filter parameters and pass them to services
- The `CommitMetricsController` has custom filtering implementations

This inconsistency makes it hard to maintain and extend the filtering capabilities.

## Decision

We will implement a consistent filtering approach that follows the hexagonal architecture principles by:

1. **Enhancing the Service Layer** to be the primary owner of filtering logic:
   - Extend the `MetricsService` with a comprehensive filtering API that handles all filter types
   - Implement filter normalization, validation, and application within the service
   - Allow services to translate high-level filter concepts into storage-specific queries

2. **Keep controllers thin**:
   - Controllers should only collect filter parameters from user input
   - No filter logic (beyond basic input validation) should exist in controllers
   - Controllers pass normalized filter parameters to services

3. **Repository layer remains focused on persistence operations**:
   - The repository should execute queries with the filters provided by the service
   - No business-specific filtering logic should exist in repositories

## Concrete Implementation Plan

1. **Extend `MetricsService` with consistent filtering methods**:
   - Create a standard filter structure that works for all metrics methods
   - Add filter normalization and validation logic
   - Ensure all metric operations support the same filtering capabilities

2. **Update controller implementations**:
   - Refactor `CommitMetricsController` to use the enhanced service layer filtering
   - Remove manual filtering logic from controllers
   - Keep controllers focused on parameter collection and response preparation

3. **Service-to-Repository Interface**:
   - Services translate high-level filters into repository-specific filters
   - The `StoragePort` interface remains clean with a standardized filtering approach

## Consequences

**Positive:**

- **Separation of Concerns**: Controllers focus on routing and presentation, services handle business logic including filtering
- **Consistency**: Unified filtering approach across all metrics operations
- **Extensibility**: New filter types can be added to the service layer without changing controllers or core use cases
- **Testability**: Filtering logic can be tested in isolation at the service layer
- **Adherence to Hexagonal Architecture**: Maintains proper separation between layers

**Negative:**

- **Migration Effort**: Existing controller-based filtering must be refactored
- **Indirect Access**: Controllers can't directly optimize queries based on UI-specific needs
- **Potentially More Abstraction**: May introduce more complexity in the service layer API

## Alternatives Considered

1. **Controller-based filtering**:
   - Would allow more UI-specific optimizations
   - But violates separation of concerns and duplicates logic across controllers

2. **Core Use Case filtering**:
   - Would centralize filtering in domain logic
   - But inappropriately mixes infrastructure concerns with pure domain concepts

3. **Repository-based filtering**:
   - Would offer the most efficient queries
   - But would duplicate business filtering logic at the infrastructure layer

The service layer approach provides the best balance of separation of concerns, reusability, and adherence to our hexagonal architecture principles. 