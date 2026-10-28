# Roadmap

What's planned, roughly in order. rails-preflight stays read-only and static: it reads the app and never changes or runs it.

## Planned

- [ ] Link each upgrade step to its RailsDiff and remind to run `bin/rails app:update`
- [ ] Detect a dual-boot setup (`Gemfile.next`, `next_rails`) and whether CI runs both Gemfiles
- [ ] Warn when `.ruby-version`, the Dockerfile and CI config disagree on Ruby
- [ ] Say which version to bump a gem to when it caps an upgrade step
- [ ] Flag secrets committed in config YAML, by file and key, never the value
- [ ] List monkeypatches on Rails and gem classes, which need rechecking on every step
- [ ] More deprecation rules for each Rails release
- [ ] Read `db/structure.sql`, not only `db/schema.rb`
- [ ] Read an existing SimpleCov result and point out findings in files the tests barely cover
- [ ] `--version`

## Not planned

- Automatic fixes or code rewriting
- Running the app or its tests
- Time estimates

Ideas and requests are welcome in [issues](https://github.com/aslam/rails-preflight/issues).
