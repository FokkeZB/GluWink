#!/usr/bin/env ruby
# frozen_string_literal: true

# sync_metadata.rb
#
# Converts the human-authored Markdown copy in `AppStore/<locale>.md` into the
# `fastlane/metadata/<locale>/*.txt` layout that `fastlane deliver` expects.
#
# Why a converter?
#   The Markdown files in `AppStore/` are the editorial source of truth — they
#   carry character-count footnotes, tone notes, and diff cleanly between
#   locales. Fastlane wants one bare text file per field per locale. Generating
#   the latter from the former keeps a single source of truth and lets us
#   regenerate before every push.
#
# Usage:
#   ruby fastlane/scripts/sync_metadata.rb            # all locales
#   ruby fastlane/scripts/sync_metadata.rb en-US      # one locale
#
# Run from inside `iOS/`. The Fastfile does that for you (`sync_metadata` lane
# and the `:before_all` hook on the `appstore` lane).

require "fileutils"
require "pathname"

REPO_ROOT     = Pathname.new(__dir__).join("..", "..", "..").realpath
APPSTORE_DIR  = REPO_ROOT.join("AppStore")
METADATA_DIR  = Pathname.new(__dir__).join("..", "metadata").expand_path

# Map "## <heading>" (case-insensitive, trailing "(NN)" or " — …" stripped) to
# the fastlane filename it should be written to. Anything not in this map is
# ignored — the Markdown can carry alternates, notes, and footnotes freely.
FIELD_MAP = {
  "app name"          => "name.txt",
  "subtitle"          => "subtitle.txt",
  "promotional text"  => "promotional_text.txt",
  "description"       => "description.txt",
  "keywords"          => "keywords.txt",
  "what's new"        => "release_notes.txt",
}.freeze

# App Store Connect's hard limits. We re-validate locally so the push fails
# loudly before reaching Apple, which is slow to error and slower to recover.
LIMITS = {
  "name.txt"             => 30,
  "subtitle.txt"         => 30,
  "promotional_text.txt" => 170,
  "description.txt"      => 4000,
  "keywords.txt"         => 100,
  "release_notes.txt"    => 4000,
}.freeze

# Parse one `<locale>.md` into { "name.txt" => "GluWink", ... }.
def parse(md_path)
  fields = {}
  current_field = nil
  in_code_block = false
  buffer = []

  md_path.each_line do |line|
    if (m = line.match(/^##\s+(.+?)\s*$/)) && !in_code_block
      flush(fields, current_field, buffer)
      current_field = normalize_heading(m[1])
      buffer = []
      next
    end

    if line.start_with?("```")
      if in_code_block
        flush(fields, current_field, buffer)
        current_field = nil
        buffer = []
      end
      in_code_block = !in_code_block
      next
    end

    buffer << line if in_code_block && current_field
  end

  fields
end

# Strip "(170)", "— v1.0 launch", trailing whitespace, lowercase.
# Repeats both passes so "## What's New (4000) — v1.0 launch" reduces to
# "what's new" regardless of suffix order.
def normalize_heading(raw)
  s = raw.dup
  loop do
    before = s
    s = s.sub(/\s*\(\d+\)\s*$/, "").sub(/\s*[—–-]\s*[^()]*$/, "")
    break if s == before
  end
  s.strip.downcase
end

def flush(fields, heading, buffer)
  return unless heading && !buffer.empty?
  filename = FIELD_MAP[heading]
  return unless filename
  fields[filename] = buffer.join.strip
end

def validate!(locale, fields)
  errors = []
  fields.each do |filename, content|
    limit = LIMITS[filename]
    next unless limit
    if content.length > limit
      errors << "  #{locale}/#{filename}: #{content.length} chars (limit #{limit})"
    end
  end
  abort("ERROR: metadata exceeds App Store limits:\n#{errors.join("\n")}") unless errors.empty?
end

def write_locale(locale, fields)
  dir = METADATA_DIR.join(locale)
  FileUtils.mkdir_p(dir)
  fields.each do |filename, content|
    path = dir.join(filename)
    path.write(content + "\n")
    puts "  wrote #{path.relative_path_from(METADATA_DIR.parent)} (#{content.length} chars)"
  end
end

def discover_locales
  Dir.glob(APPSTORE_DIR.join("*.md")).map { |p| File.basename(p, ".md") }.reject do |name|
    name == "README"
  end
end

requested = ARGV.empty? ? discover_locales : ARGV
abort("ERROR: no locales found in #{APPSTORE_DIR}") if requested.empty?

requested.each do |locale|
  md_path = APPSTORE_DIR.join("#{locale}.md")
  abort("ERROR: missing #{md_path}") unless md_path.exist?

  puts "→ #{locale}"
  fields = parse(md_path)
  if fields.empty?
    abort("ERROR: no recognised fields in #{md_path}")
  end
  validate!(locale, fields)
  write_locale(locale, fields)
end

puts "\nDone. Metadata written to #{METADATA_DIR.relative_path_from(REPO_ROOT)}/"
