# ``InsteonService``

Typed device operations, monitoring and snapshot policy for a persistent Insteon network.

## Overview

The service uses InsteonCore's device capabilities and catalog restrictions. Its application
models are independent of authentication, HTTP, HTML and serialization. Hosts open a modem
session and supply the body that runs during the service lifecycle.

Cached queries send no hardware requests. Commands retain typed status readings and report
persistence outcomes separately from hardware outcomes. One admission gate protects operations
across all adapters. Query, command and event protocols describe the roles adapters consume.

## Topics

### Client roles

- ``DeviceQuerying``
- ``DeviceCommanding``
- ``DeviceEventSource``
- ``InsteonServiceAPI``

### Models

- ``ServiceDevice``
- ``ServiceCommand``
- ``CommandReceipt``
- ``ServiceEvent``
- ``ServiceControlError``
- ``ServiceLifecycleError``

### Persistence

- ``SnapshotPersisting``
- ``NetworkSnapshotPersistence``
- ``PersistenceOutcome``
