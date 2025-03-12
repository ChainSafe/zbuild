- [x] add test, fmt tls
- [x] add options to Config
- [x] single code path for Config processing
  - always use codegen build.zig
- [x] compact union json parsing
- [x] fix how build_runner_path is set in cli
  - will be resolved by only using build.zig
- [x] robust generate cli command
  - write build.zig.zon
  - read file / write directory flags

- add named lazy paths to Config
- add named write files to Config
- add fuzz to Config
- add additional module options, eg. addIncludePath
- implement depends_on and test_runner
- refresh json schema

- lots of tests

- make json parsing errors friendly

- add init command
- add fetch command