# frozen_string_literal: true

gem "minitest", "~> 5.0"
require "minitest/autorun"
require "minitest/mock"
require "ostruct"

# Exercise the real lane without signing, uploading, or contacting Apple.
$LOADED_FEATURES << "spaceship.rb"
module Spaceship
  module ConnectAPI
    class App
      def self.find(_identifier); end
    end

    class Build
      def self.all(**_options); end
    end

  end
end

module UI
  def self.message(_text); end
  def self.success(_text); end
  def self.important(_text); end
  def self.user_error!(text) = raise(text)
end

module Actions
  def self.lane_context = { ipa: "test.ipa" }
end

module SharedValues
  IPA_OUTPUT_PATH = :ipa
end

class TestFlightLane
  attr_reader :uploads, :pointers
  attr_accessor :distribution_error

  def initialize
    @lanes = {}
    @uploads = []
    @pointers = []
    instance_eval(File.read(File.join(__dir__, "Fastfile")), "Fastfile")
  end

  def default_platform(_name); end
  def platform(_name) = yield
  def desc(_text); end
  def lane(name, &block) = @lanes[name] = block
  def is_ci = false
  def app_store_connect_api_key(**_options) = { key_id: "test-key" }
  def latest_testflight_build_number(**_options) = 153
  def get_version_number(**_options) = "1.0.0"
  def build_app(**_options); end

  def upload_to_testflight(**options)
    @uploads << options
    raise distribution_error if distribution_error && options[:distribute_external]
  end

  def run_beta
    stub(:write_api_key_file, nil) do
      stub(:revoke_stale_certificates, nil) do
        stub(:verify_healthkit_background_delivery, nil) do
          stub(:write_testflight_latest_pointer, ->(*args) { @pointers << args }) do
            ENV.stub(:fetch, "test") { @lanes.fetch(:beta).call }
          end
        end
      end
    end
  end
end

class TestFlightTest < Minitest::Test
  def setup
    @lane = TestFlightLane.new
    @groups = [
      OpenStruct.new(id: "internal", name: "Tester", is_internal_group: true),
      OpenStruct.new(id: "friends", name: "Friends Beta", is_internal_group: false)
    ]
    @app = OpenStruct.new(id: "app", get_beta_groups: @groups)
    @build = OpenStruct.new(
      processing_state: "VALID", expired: false,
      build_beta_detail: OpenStruct.new(external_build_state: "WAITING_FOR_BETA_REVIEW")
    )
  end

  def with_apple
    Spaceship::ConnectAPI::App.stub(:find, @app) do
      Spaceship::ConnectAPI::Build.stub(:all, [@build]) { yield }
    end
  end

  def test_upload_waits_for_processing_before_external_distribution
    with_apple { @lane.run_beta }
    assert_equal false, @lane.uploads.first[:skip_waiting_for_build_processing]
    assert_equal true, @lane.uploads.first[:skip_submission]
    assert_equal [["1.0.0", 154]], @lane.pointers
  end

  def test_external_build_is_submitted_for_review_and_automatic_distribution
    with_apple { @lane.run_beta }
    distribution = @lane.uploads.find { |options| options[:distribute_external] }
    refute_nil distribution, "Adding a group alone does not release a build to friends"
    assert_equal ["friends"], distribution[:groups]
    assert_equal true, distribution[:distribute_only]
    assert_equal true, distribution[:submit_beta_review]
    assert_equal true, distribution[:notify_external_testers]
    assert_equal "1.0.0", distribution[:app_version]
    assert_equal "154", distribution[:build_number]
    assert_equal "com.fitfight.mvp", distribution[:app_identifier]
    assert_equal({ key_id: "test-key" }, distribution[:api_key])
  end

  def test_distribution_failure_fails_the_lane_and_does_not_publish_an_update
    @lane.distribution_error = "Apple rejected the beta submission"
    with_apple do
      error = assert_raises(RuntimeError) { @lane.run_beta }
      assert_equal @lane.distribution_error, error.message
    end
    assert_empty @lane.pointers
  end

  def test_missing_external_group_fails_instead_of_reporting_success
    @groups.reject! { |group| !group.is_internal_group }
    with_apple { assert_raises(RuntimeError) { @lane.run_beta } }
    assert_empty @lane.pointers
  end
end
