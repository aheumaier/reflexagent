# ReflexAgent C4 Architecture Diagrams

This document serves as an index for the C4 model architecture diagrams of the ReflexAgent application. The C4 model provides a hierarchical way to describe software architecture at different levels of abstraction.

## Available Diagrams

1. [Context Diagram](c4_context_diagram.md) - Shows how ReflexAgent fits into the wider software ecosystem
2. [Container Diagram](c4_container_diagram.md) - Shows the high-level technical building blocks of ReflexAgent
3. [Component Diagram](c4_component_diagram.md) - Shows the internal components of ReflexAgent's hexagonal architecture
4. [Code Diagram](c4_code_diagram.md) - Shows the detailed class structure of the event processing pipeline

## What is the C4 Model?

The C4 model is a way to visualize software architecture that includes four levels of diagrams:

1. **Context** - System context diagram showing how the software system fits into the world around it
2. **Container** - Container diagram showing the high-level shape of the software architecture and how responsibilities are distributed
3. **Component** - Component diagram showing how a container is made up of components and their relationships
4. **Code** - Code diagram showing how a component is implemented (typically as UML class diagrams)

These diagrams help stakeholders at different levels understand the architecture:

- Non-technical stakeholders can understand the context diagram
- Technical stakeholders can understand the detailed component diagrams
- Everyone can see how the pieces fit together

## Hexagonal Architecture Implementation

ReflexAgent follows the hexagonal architecture pattern (also known as ports and adapters), which allows:

- Core business logic to be isolated from external concerns
- Easy testing of business logic through port mocks
- Flexibility to swap out adapters (database, notification systems, etc.) without changing business logic
- Enhanced maintainability by clearly separating concerns

In our diagrams, you'll see:
- The Core Domain containing domain models and use cases
- Ports defining interfaces for external interactions
- Adapters implementing these ports to connect with external systems
- Clean dependency flow from adapters → ports → core 