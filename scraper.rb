#!/usr/bin/env ruby
# frozen_string_literal: true

Bundler.require

require "scraperwiki"
require "mechanize"

class Scraper
  EN_DASH = "\u2013"

  def self.run
    a = Mechanize.new

    found = skipped = 0

    url = "https://www.ccc.tas.gov.au/planning-development/planning/advertised-planning-permit-applications/"
    a.get(url) do |page|
      page.search(".content-card__inner").each do |card|
        title_link = card.at(".content-card__title a")
        pdf_link = card.at('.content-card__buttons a[href$=".pdf"]')
        next if title_link.nil? || pdf_link.nil? || title_link.at("img")

        # Long-winded name for map link has what we need
        name = title_link.inner_text.strip
        s = name
            .split("#{EN_DASH} ")
            .map(&:strip)

        if s.count == 3
          puts "Found 3 parts as expected: #{s.inspect}"
          reference = s[0]
          address = s[1]
          description = s[2]
        elsif s.count == 2 && name =~ %r{\A(\S+-\d\d\d\d[\s/]\d+)-?\s+(\S.{15,})#{EN_DASH}\s*(.*?)\z}
          reference = ::Regexp.last_match(1)
          address = ::Regexp.last_match(2)
          description = ::Regexp.last_match(3)
          puts "Found reference #{reference.inspect}, address #{address.inspect} and description: #{description.inspect} [pattern #1]"
        elsif s.count == 2 && name =~ %r{\A(\S+-\d\d\d\d[\s/]\d+)\s*[-#{EN_DASH}]\s*(.{15,}[A-Z]{3})\s*[-#{EN_DASH}]\s*(.*?)\z}
          reference = ::Regexp.last_match(1)
          address = ::Regexp.last_match(2)
          description = ::Regexp.last_match(3)
          puts "Found reference #{reference.inspect}, address #{address.inspect} and description: #{description.inspect} [pattern #2]"
        else
          # Skip over unrecognized formats
          puts "WARNING: Skipping unparsable map link: #{name.inspect}"
          skipped += 1
          next
        end
        found += 1
        unless address =~ / TAS\s^$/
          puts "  appended missing ', TAS' to address" if ENV["DEBUG"]
          address = "#{address}, TAS"
        end

        begin
          record = {
            "council_reference" => reference,
            "address" => address,
            "description" => description,
            "date_scraped" => Date.today.to_s,
            "info_url" => pdf_link["href"],
          }

          ScraperWiki.save_sqlite(["council_reference"], record)
        rescue StandardError => e
          puts "  Ignored erroneous record: #{e.class.name}: #{e.message}"
        end
      end
      puts "",
           "Found #{found} records, skipping #{skipped} unrecognisable links"
    end
  end
end

Scraper.run if __FILE__ == $PROGRAM_NAME
