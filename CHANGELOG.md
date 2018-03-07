# Changelog

## [0.1.7] - 2018-03-12
### Added
- Renamed project to `gen_rmq` @mkorszun.
- Renamed namespace from `GenAMQP` to `GenRMQ` @mkorszun.

## [0.1.6] - 2018-03-02
### Added
- Required project configuration to publish on [hex.pm](hex.pm) @mkorszun.

## [0.1.5] - 2018-02-28
### Added
- Possibility to control concurrency in consumer @mkorszun.
- Possibility to make `app_id` configurable for publisher @mkorszun.
- Better `ExDoc` documentation

### Fixed
- If `queue_ttl` specified it also applies to dead letter queue @mkorszun.
- Default `routing_key` on publish

## [0.1.4] - 2018-02-06
### Added
- Possibility to specify queue ttl in consumer config @mkorszun.

## [0.1.3] - 2018-01-31
### Added
- Processor behaviour @mkorszun.
### Removed
- Unused test helper functions @mkorszun.

[0.1.7]: https://github.com/meltwater/gen_rmq/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/meltwater/gen_rmq/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/meltwater/gen_rmq/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/meltwater/gen_rmq/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/meltwater/gen_rmq/compare/v0.1.2...v0.1.3
