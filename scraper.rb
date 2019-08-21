require 'scraperwiki'
require 'open-uri'
require "pdf-reader"
require 'mechanize'
require "base64"

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

def evaluate_expression(expression)
  items = expression.split("+").map{|s| s.strip.gsub('"', "'")}
  items.delete("''")
  evaluated_items = items.map do |item|
    if item =~ %r{^'([^']*)'$}
      $1
    elsif item =~ %r{'([^']*)'.slice\((\d+),(\d+)\)}
      $1.slice($2.to_i, $3.to_i)
    elsif item =~ %r{'([^']*)'.charAt\((\d+)\)}
      $1[$2.to_i]
    elsif item =~ %r{'([^']*)'.substr\((\d+),\s?(\d+)\)}
      $1[$2.to_i..($2.to_i+$3.to_i-1)]
    elsif item =~ %r{String.fromCharCode\((0x[0-9a-f]+)\)}
      $1.to_i(16).chr
    elsif item =~ %r{String.fromCharCode\((\d+)\)}
      $1.to_i.chr
    else
      raise "Don't know how to handle: #{item}"
    end
  end
  evaluated_items.join
end

a = Mechanize.new

# Oh great. Thanks. This site is "protected" from scraping by a scheme that's just "work" to get around
# Why do this? It's futile. It's extremely bad for accessibility
# It's using https://sucuri.net/ which is owned by GoDaddy. So, basically super dodgy.

url = "https://www.ccc.tas.gov.au/planning-development/planning/advertised-planning-permit-applications/"
a.get(url) do |page|
  script = page.at("script").inner_text
  s = script.match(%r{S='([^']*)';})[1]
  raise "Unexpected form of script" unless script == "var s={},u,c,U,r,i,l=0,a,e=eval,w=String.fromCharCode,sucuri_cloudproxy_js='',S='#{s}';L=S.length;U=0;r='';var A='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';for(u=0;u<64;u++){s[A.charAt(u)]=u;}for(i=0;i<L;i++){c=s[S.charAt(i)];U=(U<<6)+c;l+=6;while(l>=8){((a=(U>>>(l-=8))&0xff)||(i<(L-2)))&&(r+=w(a));}}e(r);"
  # String is base64 encoded
  js_expr = Base64.decode64(s)
  s_expr = js_expr.match(/s=(.*);document\.cookie=(.*); location\.reload\(\);/m)[1]
  d_expr = js_expr.match(/s=(.*);document\.cookie=(.*); location\.reload\(\);/m)[2]

  s = evaluate_expression(s_expr)
  d_expr = d_expr.gsub(" s ", " '#{s}' ")
  d = evaluate_expression(d_expr)
  # The final cookie
  cookie = Mechanize::Cookie.parse(URI("https://www.ccc.tas.gov.au"), d)[0]
  a.cookie_jar << cookie
  page = a.get(url)

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
