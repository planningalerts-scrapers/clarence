require 'scraperwiki'
require 'mechanize'

a = Mechanize.new

url = "https://www.ccc.tas.gov.au/planning-development/planning/advertised-planning-permit-applications/"
a.get(url) do |page|
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
