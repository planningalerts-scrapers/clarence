require 'scraperwiki'
require 'mechanize'

a = Mechanize.new

EN_DASH = "\u2013"

url = "https://www.ccc.tas.gov.au/planning-development/planning/advertised-planning-permit-applications/"
a.get(url) do |page|
  page.search('.content-card__inner').each do |card|
    title_link = card.at('.content-card__title a')
    pdf_link = card.at('.content-card__buttons a[href$=".pdf"]')
    next if title_link.nil? || pdf_link.nil? || title_link.at('img')

    # Long-winded name for map link has what we need
    name = title_link.inner_text.strip
    s = name
          .sub("- Advertising period expires", "#{EN_DASH} Advertising period expires")
          .split("#{EN_DASH} ")
          .map(&:strip)

    # Skip over links that we don't know how to handle
    if s.count != 4
      puts "WARNING: Skipping map link with #{s.count} rather than 4 parts: #{s.inspect}"
      next
    end

    puts "Found: #{s.inspect}"
    record = {
      'council_reference' => s[0],
      'address' => s[1] + ", TAS",
      'description' => s[2],
      'on_notice_to' => Date.parse(s[3]).to_s,
      'date_scraped' => Date.today.to_s,
      'info_url' => pdf_link['href']
    }

    ScraperWiki.save_sqlite(['council_reference'], record)
  end
end
