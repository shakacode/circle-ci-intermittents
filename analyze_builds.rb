#!/usr/bin/env ruby
require "date"
require "json"

BUILDS_START = 30_000
BUILDS_END = 45_825

MONDAY = Date.parse("Monday") - 7 # script is supposed to run next monday to capture weekend errors
WEEK1 = MONDAY..(MONDAY + 6)
WEEK2 = (MONDAY - 7)..(MONDAY - 1)
WEEK3 = (MONDAY - 14)..(MONDAY - 8)
WEEK4 = (MONDAY - 21)..(MONDAY - 15)
WEEK5 = (MONDAY - 28)..(MONDAY - 22)

CI_TOKEN = File.read("ci_secret_token.txt").tr("\n\r", "")

CI_BUILDS_PATH = "ci-builds".freeze
CI_BUILD_LOGS_PATH = "ci-build-logs".freeze
CI_PROJECT_URL = "https://circleci.com/gh/shakacode/friendsandguests/".freeze

class AnalyzeBuilds
  def start
    puts "Loading CI builds..."
    all_builds
    puts "Finished"

    failed_specs1 = failed_specs_for(all_builds(WEEK1))
    failed_specs2 = failed_specs_for(all_builds(WEEK2))
    failed_specs3 = failed_specs_for(all_builds(WEEK3))
    failed_specs4 = failed_specs_for(all_builds(WEEK4))
    failed_specs5 = failed_specs_for(all_builds(WEEK5))

    specs = failed_specs1.
            merge(failed_specs2).
            merge(failed_specs3).
            merge(failed_specs4).
            merge(failed_specs5)

    specs.keys.sort.each do |spec|
      qty1 = failed_specs1[spec] || 0
      qty2 = failed_specs2[spec] || 0
      qty3 = failed_specs3[spec] || 0
      qty4 = failed_specs4[spec] || 0
      qty5 = failed_specs5[spec] || 0

      puts "#{qty5} #{qty4} #{qty3} #{qty2} #{qty1} #{spec}"
    end

    logs_for(all_builds(WEEK1)).each do |log|
      puts "\n#{CI_PROJECT_URL}#{log.build_num}"
      log.failed_specs.each { |spec| puts spec }
    end
  end

  def failed_specs_for(builds)
    failed_specs = {}
    logs_for(builds).each do |log|
      log.failed_specs.each do |spec|
        failed_specs[spec] = (failed_specs[spec] || 0) + 1
      end
    end
    failed_specs
  end

  def logs_for(builds)
    logs = []
    fixed_commits_for(builds).each_key do |commit|
      builds_of_commit(builds, commit).each do |build|
        build.data["steps"].each do |step|
          next unless step["name"] == "Run tests"
          step["actions"].each do |action|
            next unless action["failed"]
            logs << CILog.new(build.num, action["index"], action["output_url"])
          end
        end
      end
    end
    logs
  end

  def builds_of_commit(builds, commit)
    builds.clone.keep_if { |build| build.commit == commit }
  end

  def fixed_commits_for(builds)
    retried_commits_for(builds).clone.delete_if { |k, _| builds_of_commit(builds, k).none?(&:fixed?) }
  end

  def retried_commits_for(builds)
    attempts_by_commit_for(builds).clone.delete_if { |_, v| v == 1 }
  end

  def attempts_by_commit_for(builds)
    attempts_by_commit = {}
    builds.each do |build|
      attempts_by_commit[build.commit] = (attempts_by_commit[build.commit] || 0) + 1
    end
    attempts_by_commit
  end

  def all_builds(range = nil)
    builds = []
    (BUILDS_START..BUILDS_END).each do |n|
      build = CIBuild.new(n)
      builds << build if !build.canceled? && build.rspec_build? && (!range.nil? && range === build.run_date)
    end
    builds
  end
end

class CILog
  attr_reader :build_num
  attr_reader :index
  attr_reader :url

  def initialize(build_num, index, url)
    @build_num = build_num
    @index = index
    @url = url
  end

  def failed_specs
    @failed_specs ||= data.scan(/rspec \.\/([^:]+:\d+.*\r\n)/).flatten
  end

  def data
    @data ||= load_log[0]["message"]
  end

  def load_log
    curl_get_log unless File.file?(log_filename)
    JSON.parse(File.read(log_filename))
  rescue StandardError => e
    puts "\nError in #{log_filename}, please reload file"
    raise e
  end

  def curl_get_log
    puts "\nLoading log from container #{index} for build #{build_num}"
    `curl --compressed "#{url}" > #{log_filename}`
  end

  def log_filename
    "#{CI_BUILD_LOGS_PATH}/#{build_num}-#{index}"
  end
end

class CIBuild
  @@builds_data = []

  attr_reader :num

  def initialize(num)
    @num = num
  end

  def data
    @@builds_data[num] || load_build
  end

  def load_build
    curl_get_build unless File.file?(build_filename)
    @@builds_data[num] = JSON.parse(File.read(build_filename))
  rescue StandardError => e
    puts "\nError in #{build_filename}, please reload file"
    raise e
  end

  def rspec_build?
    data.dig("build_parameters", "CIRCLE_JOB") == "rspec"
  end

  def canceled?
    data["canceled"]
  end

  def fixed?
    data["status"] == "fixed"
  end

  def curl_get_build
    puts "\nLoading build #{num}"
    url = "https://circleci.com/api/v1.1/project/github/shakacode/friendsandguests/#{num}"
    `curl -u #{CI_TOKEN}: #{url} > #{build_filename}`
  end

  def build_filename
    "#{CI_BUILDS_PATH}/#{num}"
  end

  def filtered_params
    %w[outcome vcs_revision build_num queued_at steps]
  end

  def run_date
    Date.parse(data["start_time"]).to_date
  end

  def commit
    data["vcs_revision"]
  end
end

AnalyzeBuilds.new.start
