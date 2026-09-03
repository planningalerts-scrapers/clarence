#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
Bundler.require

require "scraperwiki"
require "mechanize"

# Scrapes advertised planning permit applications from Clarence City Council
class Scraper
  EN_DASH = "\u2013"

  URL = "https://www.ccc.tas.gov.au/development/advertised-plans/"

  # e.g. "PDPLANPMTD-2026/063010", "PDPLANPMTD-2026-063175" or "PDPLANPMTD-2025 051945"
  REFERENCE = %r{\A\S+-\d{4}[\s/-]\d+\z}

  # Trailing parts like "Ad Ends 31 Aug 2026", "Ad End 31Aug2026" or "Effective 7 July 2026"
  TRAILER = /\A(?:Ad\s*Ends?|Effective)\b/i

  # A street number followed by a comma separated suburb, e.g. "6 Parrott Place, Tranmere"
  ADDRESS = /\d+[A-Za-z]?\s.+,\s*\S+/

  def self.run
    agent = Mechanize.new
    found = skipped = 0
    page = agent.get(URL)
    page.search(".content-card__inner").each do |card|
      title_link = card.at(".content-card__title a")
      # Documents are usually direct .pdf links but some use
      # https://resources.ccc.tas.gov.au/public/<id> style links
      pdf_link = card.at('.content-card__buttons a[href$=".pdf"]') ||
                 card.at(".content-card__buttons a")
      next if title_link.nil? || pdf_link.nil? || title_link.at("img")

      # Long-winded name for map link has what we need
      parsed = parse_map_link(title_link.inner_text.strip)
      if parsed.nil?
        skipped += 1
        next
      end
      found += 1
      save_record(*parsed, pdf_link["href"])
    end
    puts "", "Found #{found} records, skipping #{skipped} unrecognisable links"
    puts "Finished - added #{found} records"
  end

  # Titles are en-dash separated. The council has used both
  # "REF - ADDRESS - DESCRIPTION" and "REF - DESCRIPTION - ADDRESS" orders,
  # sometimes with extra en-dashes inside the description and a trailing
  # "Ad Ends <date>" / "Effective <date>" part, so the address is located
  # by shape rather than position.
  def self.parse_map_link(name)
    parts = name.split(/\s*#{EN_DASH}\s*/o).map(&:strip).reject(&:empty?)
    parts.shift if parts.first == "Clarence"
    reference = parts.shift
    parts.pop while parts.any? && parts.last.match?(TRAILER)
    address_index = parts.rindex { |part| part.match?(ADDRESS) }
    unless reference&.match?(REFERENCE) && address_index && parts.size >= 2
      puts "WARNING: Skipping unparsable map link: #{name.inspect}"
      return nil
    end
    address = parts.delete_at(address_index)
    description = parts.join(" #{EN_DASH} ")
    puts "Found #{reference.inspect}: #{description.inspect} at #{address.inspect}"
    [reference, address, description]
  end

  def self.save_record(reference, address, description, info_url)
    unless address.match?(/\bTAS\b/i)
      puts "  appended missing ', TAS' to address" if ENV["DEBUG"]
      address = "#{address}, TAS"
    end
    record = {
      "council_reference" => reference,
      "address" => address,
      "description" => description,
      "date_scraped" => Date.today.to_s,
      "info_url" => info_url,
    }
    ScraperWiki.save_sqlite(["council_reference"], record)
  rescue StandardError => e
    puts "  Ignored erroneous record: #{e.class.name}: #{e.message}"
  end
end

Scraper.run if __FILE__ == $PROGRAM_NAME
