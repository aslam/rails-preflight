# mastodon: Rails 5.2.4.4 to 7.0

3 steps, and Ruby 2.7.2 can stay. 13 blockers, 9 of them gems.

Already broken: 0 · Blockers: 13 · To fix: 9 · Couldn't check: 3

> For a coding agent: take one step at a time, in order. After each step, run the test suite and fix what fails before starting the next. Leave "Ahead" and "Couldn't check" alone unless asked.

## Before you start (on Rails 5.2.4.4)

- [ ] **To fix:** Ruby 2.7.2 is end-of-life. Rails 7.0 supports up to Ruby 3.2; Ruby 3.3+ needs Rails 7.1.
- [ ] **To fix:** No ENV LANG or LC_ALL set, which can cause encoding errors.
- [ ] **To fix:** paperclip is deprecated and archived. Move to Active Storage, or to the maintained kt-paperclip fork. Used in 8 files. ([source](https://github.com/thoughtbot/paperclip#deprecated))
  - `app/models/backup.rb`
  - `app/models/concerns/account_avatar.rb`
  - `app/models/concerns/account_header.rb`
  - `app/models/custom_emoji.rb`
  - `app/models/import.rb`
  - `app/models/media_attachment.rb`
  - `app/models/preview_card.rb`
  - `app/models/site_upload.rb`
- [ ] **To fix:** webpacker was retired after Rails 7.0. Move to jsbundling-rails or import maps, or to shakapacker to keep webpack. Used in 28 files. ([source](https://github.com/rails/webpacker#readme))
  - `app/views/about/more.html.haml`
  - `app/views/admin/action_logs/index.html.haml`
  - `app/views/admin/custom_emojis/index.html.haml`
  - `app/views/admin/domain_allows/new.html.haml`
  - `app/views/admin/domain_blocks/edit.html.haml`
  - `app/views/admin/domain_blocks/new.html.haml`
  - `app/views/admin/ip_blocks/index.html.haml`
  - `app/views/admin/pending_accounts/index.html.haml`
  - `app/views/admin/reports/show.html.haml`
  - `app/views/admin/settings/edit.html.haml`
  - `app/views/admin/statuses/index.html.haml`
  - `app/views/admin/tags/index.html.haml`
  - `app/views/auth/sessions/two_factor.html.haml`
  - `app/views/home/index.html.haml`
  - `app/views/layouts/admin.html.haml`
  - `app/views/layouts/application.html.haml`
  - `app/views/layouts/auth.html.haml`
  - `app/views/layouts/embedded.html.haml`
  - `app/views/layouts/error.html.haml`
  - `app/views/layouts/mailer.html.haml`
  - `app/views/layouts/modal.html.haml`
  - `app/views/layouts/public.html.haml`
  - `app/views/media/player.html.haml`
  - `app/views/public_timelines/show.html.haml`
  - `app/views/relationships/show.html.haml`
  - `app/views/settings/two_factor_authentication/webauthn_credentials/new.html.haml`
  - `app/views/shares/show.html.haml`
  - `app/views/tags/show.html.haml`

## Step 1: 5.2.4.4 to 6.0

Needs Ruby 2.5.0–2.7: 2.7.2 works.

- [ ] **Blocker:** nsa 0.2.7 requires activesupport >= 4.2, < 6, so it doesn't install on Rails 6.0. Upgrade it to a release that allows 6.0, or replace it.
- [ ] **Blocker:** rails-i18n 5.1.3 requires railties >= 5.0, < 6, so it doesn't install on Rails 6.0. Upgrade it to a release that allows 6.0, or replace it.

## Step 2: 6.0 to 6.1

Needs Ruby 2.5.0–3.0: 2.7.2 works.

- [ ] **Blocker:** active_model_serializers 0.10.10 requires actionpack >= 4.1, < 6.1, activemodel >= 4.1, < 6.1, so it doesn't install on Rails 6.1. Upgrade it to a release that allows 6.1, or replace it.
- [ ] **Blocker:** devise-two-factor 3.1.0 requires activesupport < 6.1, railties < 6.1, so it doesn't install on Rails 6.1. Upgrade it to a release that allows 6.1, or replace it.
- [ ] **Blocker:** bullet 6.1.0 doesn't load on Rails 6.1: Bullet raises on an Active Record minor it doesn't know; Rails 6.1 needs bullet >= 6.1.1. Upgrade it in the same step. ([source](https://github.com/flyerhzm/bullet/blob/8.1.0/lib/bullet/dependency.rb))
- [ ] **Blocker:** `force_ssl` at the controller level was removed in Rails 6.1. Use `config.force_ssl` to force HTTPS for the whole app. ([source](https://guides.rubyonrails.org/6_1_release_notes.html#action-pack-removals))
  - `app/controllers/application_controller.rb:8` `force_ssl if: :https_enabled?`

## Step 3: 6.1 to 7.0

Needs Ruby 2.7.0–3.2: 2.7.2 works.

- [ ] **Blocker:** annotate 3.1.1 requires activerecord >= 3.2, < 7.0, so it doesn't install on Rails 7.0. Upgrade it to a release that allows 7.0, or replace it.
- [ ] **Blocker:** discard 1.2.0 requires activerecord >= 4.2, < 7, so it doesn't install on Rails 7.0. Upgrade it to a release that allows 7.0, or replace it.
- [ ] **Blocker:** redis-actionpack 5.2.0 requires actionpack >= 5, < 7, so it doesn't install on Rails 7.0. Upgrade it to a release that allows 7.0, or replace it.
- [ ] **Blocker:** redis-activesupport 5.2.0 requires activesupport >= 3, < 7, so it doesn't install on Rails 7.0. Upgrade it to a release that allows 7.0, or replace it.
- [ ] **Blocker:** Changing error messages in place (errors[:attr] << msg, errors.messages[:attr] = ..., errors.messages.delete/clear) was removed in Rails 7.0: it now changes a copy, so the error is silently lost. Use errors.add, errors.delete and errors.clear. ([source](https://guides.rubyonrails.org/7_0_release_notes.html#active-model-removals))
  - `app/validators/ed25519_key_validator.rb:9` `record.errors[attribute] << I18n.t('crypto.errors.invalid_key') unless verified?(key)`
  - `app/validators/ed25519_signature_validator.rb:11` `record.errors[attribute] << I18n.t('crypto.errors.invalid_signature') unless verified?(verify_key, signature, message)`
- [ ] **Blocker:** `ActionMailer::DeliveryJob` and `ActionMailer::Parameterized::DeliveryJob` were removed in Rails 7.0. Mail is delivered by `ActionMailer::MailDeliveryJob`. ([source](https://guides.rubyonrails.org/7_0_release_notes.html#action-mailer-removals))
  - `config/initializers/delivery_job.rb:1` `ActionMailer::DeliveryJob.class_eval do`
  - `spec/models/user_spec.rb:178` `expect { user.send_confirmation_instructions }.to have_enqueued_job(ActionMailer::DeliveryJob)`
- [ ] **Blocker:** `ActiveModel::Errors#keys`, `#values`, `#to_h`, `#slice!` and `#to_xml` were removed in Rails 7.0. Use errors.attribute_names, errors.to_hash or the ActiveModel::Error objects errors.each yields. ([source](https://guides.rubyonrails.org/7_0_release_notes.html#active-model-removals))
  - `lib/mastodon/accounts_cli.rb:106` `user.errors.to_h.each do |key, error|`
  - `lib/mastodon/accounts_cli.rb:172` `user.errors.to_h.each do |key, error|`
  - `spec/support/matchers/model/model_have_error_on_field.rb:11` `keys = record.errors.keys`

## Ahead: removed in 7.2, not needed for 7.0

- [ ] **To fix:** Setting `config.action_dispatch.show_exceptions` to true or false was removed in Rails 7.2. Use :all (was true), :rescuable, or :none (was false). ([source](https://guides.rubyonrails.org/7_2_release_notes.html#action-pack-removals))
  - `config/environments/test.rb:31` `config.action_dispatch.show_exceptions = false`
- [ ] **To fix:** `Rails.application.secrets` was removed in Rails 7.2. Use credentials, or Rails.application.config_for for non-secret settings. ([source](https://guides.rubyonrails.org/7_2_release_notes.html#railties-removals))
  - `config/routes.rb:6` `Sidekiq::Web.set :session_secret, Rails.application.secrets[:secret_key_base]`
- [ ] **To fix:** `fixture_path` was removed in Rails 7.2. Assign `fixture_paths` instead, which takes an array. ([source](https://guides.rubyonrails.org/7_2_release_notes.html#active-record-removals))
  - `spec/rails_helper.rb:37` `config.fixture_path = "#{::Rails.root}/spec/fixtures"`

## Ahead: removed in 8.0, not needed for 7.0

- [ ] **To fix:** Defining `enum` with keyword arguments was removed in Rails 8.0. Pass the name positionally, e.g. enum :status, { pending: 0 }. ([source](https://guides.rubyonrails.org/8_0_release_notes.html#active-record-removals))
  - `app/models/account.rb:78` `enum protocol: [:ostatus, :activitypub]`
  - `app/models/account.rb:79` `enum suspension_origin: [:local, :remote], _prefix: true`
  - `app/models/account_warning.rb:16` `enum action: %i(none disable sensitive silence suspend), _suffix: :action`
  - `app/models/domain_block.rb:22` `enum severity: [:silence, :suspend, :noop]`
  - `app/models/import.rb:27` `enum type: [:following, :blocking, :muting, :domain_blocking, :bookmarks]`
  - `app/models/ip_block.rb:20` `enum severity: {`
  - `app/models/list.rb:19` `enum replies_policy: [:list, :followed, :none], _prefix: :show`
  - `app/models/media_attachment.rb:34` `enum type: [:image, :gifv, :video, :unknown, :audio]`
  - `app/models/media_attachment.rb:35` `enum processing: [:queued, :in_progress, :complete, :failed], _prefix: true`
  - `app/models/preview_card.rb:40` `enum type: [:link, :photo, :video, :rich]`
  - `app/models/relay.rb:17` `enum state: [:idle, :pending, :accepted, :rejected]`
  - `app/models/status.rb:47` `enum visibility: [:public, :unlisted, :private, :direct, :limited], _suffix: :visibility`
  - `db/migrate/20190511134027_add_silenced_at_suspended_at_to_accounts.rb:8` `enum severity: [:silence, :suspend, :noop]`
  - `db/post_migrate/20190511152737_remove_suspended_silenced_account_fields.rb:10` `enum severity: [:silence, :suspend, :noop]`

## Ahead: removed in 8.1, not needed for 7.0

- [ ] **To fix:** `STATS_DIRECTORIES` was removed in Rails 8.1. Register extra directories with Rails::CodeStatistics.register_directory(`Services`, `app/services`). ([source](https://guides.rubyonrails.org/8_1_release_notes.html#railties-removals))
  - `lib/tasks/statistics.rake:16` `::STATS_DIRECTORIES << [name, Rails.root.join(dir)]`

## Couldn't check

- Private gems (2): compatibility with Rails 7.0 is unknown: health_check, nilsimsa
- Could not detect a versioned ruby base image in Dockerfile.
- 5 gems that depend on Rails had no release since before Rails 7.0 shipped (2021-12-15). Check they work on 7.0, or find replacements.: case_transform (last release 2016-09-22), hamlit-rails (last release 2019-04-08), rails-controller-testing (last release 2020-06-23), makara (last release 2021-06-04), pluck_each (last release 2021-09-21)

Made with [rails-preflight](https://github.com/aslam/rails-preflight) 0.1.0. Run it again after each step.
