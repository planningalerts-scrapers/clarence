require 'scraperwiki'
require 'open-uri'
require "pdf-reader"
require 'mechanize'

class PageTextReceiver
  attr_accessor :content

  def initialize
    @content = []
  end

  # Called when page parsing starts
  def begin_page(arg = nil)
    @content << ""
  end

  # record text that is drawn on the page
  def show_text(string, *params)
    @content.last << string
  end

  # there's a few text callbacks, so make sure we process them all
  alias :super_show_text :show_text
  alias :move_to_next_line_and_show_text :show_text
  alias :set_spacing_next_line_show_text :show_text

  # this final text callback takes slightly different arguments
  def show_text_with_positioning(*params)
    params = params.first
    params.each { |str| show_text(str) if str.kind_of?(String)}
  end
end

def scrape_pdf(url)
  begin
    o = open(url)
  rescue Exception
    puts "Couldn't load #{url}"
    return nil
  end
  receiver = PageTextReceiver.new
  reader = PDF::Reader.new
  reader.parse(o, receiver)
  text = receiver.content.join
  puts text
  match = text.match(/(DEVELOPMENT|SUBDIVISION) APPLICATION(.*)APPLICANT:(.*)PROPOSAL:(.*)LOCATION:(.*)ADVERTISING EXPIRY DATE:([^.]*)\./)
  if match.nil?
    puts "WARNING: Returned text isn't matching regular expression"
    nil
  else
    {
      'council_reference' => match[2],
      'description' => match[4],
      'address' => match[5] + ", TAS",
      'info_url' => url,
      'comment_url' => 'mailto:clarence@ccc.tas.gov.au',
      'on_notice_to' => Date.parse(match[6]).to_s,
      'date_scraped' => Date.today.to_s
    }
  end
end

a = Mechanize.new

# Oh great. Thanks. This site is "protected" from scraping by a scheme that's just "work" to get around
# Why do this? It's futile. It's extremely bad for accessibility
# It's using https://sucuri.net/ which is owned by GoDaddy. So, basically super dodgy.

# First, naive stab at this assumes that the cookies never have to change. So, hardcoding
# two cookies that get set by the site that allow it to be loaded.
cookie1 = Mechanize::Cookie.new domain: ".www.ccc.tas.gov.au", name: "sucuri_cloudproxy_uuid_7f1fb16fe", value: "2be47d328df84f3ed16371eef41e2e1c", path: "/"
cookie2 = Mechanize::Cookie.new domain: ".www.ccc.tas.gov.au", name: "sucuri_cloudproxy_uuid_0755cafd7", value: "2250934b40bf9b8e6556017a3c643e31", path: "/"
a.cookie_jar << cookie1
a.cookie_jar << cookie2

a.get("https://www.ccc.tas.gov.au/planning-development/planning/advertised-planning-permit-applications/") do |page|
  page.search('.doc-list a').each do |a|
    unless a.at('img')
      # Long winded name of PDF
      name = a.inner_text.strip
      s = name.split(' - ').map(&:strip)
      # Skip over links that we don't know how to handle
      if s.count != 4
        puts "Unexpected form of PDF name. So, skipping: #{name}"
        next
      end

      record = {
        'council_reference' => s[0],
        'address' => s[1] + ", TAS",
        'description' => s[2],
        'on_notice_to' => Date.parse(s[3]).to_s,
        'date_scraped' => Date.today.to_s,
        'info_url' => (page.uri + a["href"]).to_s
      }

      ScraperWiki.save_sqlite(['council_reference'], record)
    end
  end
end
