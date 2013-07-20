require 'nokogiri'
require 'open-uri'
require 'parallel'
require 'httparty'
require 'csv'

class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end

  def present?
    !blank?
  end
end

def main
  puts 'start'
  cg = HTTParty.get('http://www.craigslist.org/about/sites',
            headers: {'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/27.0.1453.116 Safari/537.36',
            'Connection' => 'keep-alive',
            'Accept-Encoding' => 'gzip'}
  )
  puts 'opened main site'
  cg_doc = Nokogiri.HTML(cg)
  # links to all US and CA sites with 'buildium' results
  sites = cg_doc.css('div.colmask')[0..1].map{|d|d.css('a').map{|a|a['href']}}.flatten.uniq
  c_links = Parallel.map(sites, in_processes: 4) do |s|
    ret = 5
    begin
      puts "links for site #{s} ..."
      cls = contact_links(s)
      cls
    rescue => e
      puts "exception with site: #{s} : #{e}"
      if (ret = ret - 1) > 0
        puts "retrying for site : #{s}"
        retry
      else
        puts e.backtrace
      end
    end
  end.flatten.uniq
  puts 'end links for sites'
  infos = Parallel.map(c_links, in_threads: 50) do |cl|
    ret = 5
    begin
      puts "info for contact link #{cl} ..."
      contact_info(cl)
    rescue => e
      puts "error: #{e} for #{cl}"
      if (ret = ret - 1) > 0
        puts "retrying for #{cl}"
        retry
      end
    end
  end.compact
  sanitized_infos = infos.map{|i|sanitize_info(i)}.compact
  csv_string = CSV.generate do |csv|
    sanitized_infos.each do |info|
      csv << info
    end
  end
  File.open('craigsbuildium.csv','w'){|f|f.write(csv_string)}
  puts csv_string
end

def sanitize_info(nfo)
  begin
    nfo = nfo.clone
    link = nfo.shift
    company = nfo.shift
    email = nfo.grep(EMAIL_REGEX).select(&:present?).first
    nfo.delete(email) if email.present?
    phones = nfo.grep(PHONE_REGEX).select(&:present?)
    phones.each{|p|nfo.delete(p)}
    phones = phones.join(',')
    nfo.delete('')
    townzip = nfo.pop
    city, statezip = townzip.split(',') if townzip
    state, zip = statezip.split(' ') if statezip
    address = nfo.join(',')
    [link.match(/.*managebuilding\.com/)[0], company, address, city||townzip, state, zip, phones, email]
  rescue => e
    puts 'error in sanitizing info: '
    puts nfo
    puts e
    puts e.backtrace
    nil
  end
end

def contact_info(link)
  g = HTTParty.get(link, no_follow: true) rescue nil # in case when 'contacts' page doesn't exist
  return nil if g.nil?
  nfo = Nokogiri.HTML(g).at_css('#_ctl0_contentPlaceHolderBody_ucSideBox_lblBody').inner_html.split('<br>')
  nfo.delete_at(1)
  nfo.unshift(link)
  nfo
end

def contact_links(link)
  ll = listing_links(link+'/search/apa?query=buildium').map{|l|l.start_with?('http') ? l : (link+l)}
  Parallel.map(ll, threads: 20) do |l|
    buildium_subdomains(l)
  end.flatten.uniq.map{|sd|"https://#{sd}.managebuilding.com/Resident/PublicPages/ContactUs.aspx"}
end

def buildium_subdomains(page_link)
  # sometimes page just don't work so..
  begin
    pg_doc = Nokogiri.HTML(HTTParty.get(page_link, timeout: 10, headers: {'Accept-Encoding' => 'gzip'}))
    sds = pg_doc.css('a').map{|a|a['href']}.compact.map{|l|l.match(/:\/\/([a-z0-9\-_]+)\.managebuilding\.com/)}.compact.map{|m|m[1]}.uniq
    puts "#{page_link} have not so unique buildium subdomains it seems" if sds.size > 1
    sds
  rescue
    puts "can't catch page #{page_link}"
    []
  end
end

def listing_links(link, total = nil, start = 0)
  site = Nokogiri.HTML(HTTParty.get("#{link}&s=#{start}", timeout: 10, headers: {'Accept-Encoding' => 'gzip'}))
  puts "#{link}&s=#{start}"
  add_pages = site.css('span.pagelinks a').map{|a|a['href']}.uniq
  total ||= site.css('.resulttotal').text.match(/[\d]+/)[0].to_i rescue 0
  site_pages = [site] + add_pages.map{|p|Nokogiri.HTML(HTTParty.get(p, timeout: 30))}
  pages = site_pages.map{|p|p.at_css('#toc_rows').css('p.row a').map{|a|a['href']}}.flatten.reject{|h|h=='#'}
  if total > 100
    pages = pages + listing_links(link, total-100, start+100)
  end
  pages
end

EMAIL_REGEX =  /^(|(([A-Za-z0-9]+_+)|([A-Za-z0-9]+\-+)|([A-Za-z0-9]+\.+)|([A-Za-z0-9]+\++))*[A-Za-z0-9]+@((\w+\-+)|(\w+\.))*\w{1,63}\.[a-zA-Z]{2,6})$/i
PHONE_REGEX = /^((\([\d]+\).*)|(.*\([\d.]{5,}\))|([\d.\- \(\)\/]+\((fax|office)\))?|([\d.\- \(\)\/]{10,}.*)|([\d\-]{8,}.*)|(Joey Gonzalez Cell \(fax\)))$/

main

