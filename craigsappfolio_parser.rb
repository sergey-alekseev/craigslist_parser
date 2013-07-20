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
      ci = contact_info(cl)
      ci.map(&:to_s) if ci.present?
    rescue => e
      puts "error: #{e} for #{cl}"
      if (ret = ret - 1) > 0
        puts "retrying for #{cl}"
        retry
      end
    end
  end.uniq.compact
  puts infos.inspect
  csv_string = CSV.generate do |csv|
    infos.each do |info|
      csv << info
    end
  end
  File.open('craigsappfolio.csv','w'){|f|f.write(csv_string)}
  puts csv_string
end

def contact_info(link)
  g = HTTParty.get(link, no_follow: true) rescue nil # in case when 'contacts' page doesn't exist
  return nil if g.nil?
  info = Nokogiri.HTML(g).at_css('#contact_info')
  if info.nil?
    [link.match(/https?:\/\/([a-z0-9\-_]+\.appfolio\.com).*/)[1], nil, nil, nil]
  else
    links = info.css('a')
    email = links.select{|l|l['href'] =~ /mailto:/}.map{|l|l['href'][7,100500]}.reject{|m|m=='donotreply@appfolio.com'}.first
    site = links.select{|l|l['href'] !~ /mailto:/}.map{|l|l['href']}.first
    name = info.css('strong').text
    phone = info.xpath('p/child::text()')
    phone = phone.text if phone.present?
    [name, phone, site, email]
  end

end

def contact_links(link)
  ll = listing_links(link+'/search/apa?query=appfolio').map{|l|l.start_with?('http') ? l : (link+l)}
  Parallel.map(ll, threads: 20) do |l|
    listings(l)
  end.flatten.uniq
end

def listings(page_link)
  # sometimes page just don't work so..
  begin
    pg_doc = Nokogiri.HTML(HTTParty.get(page_link, timeout: 10, headers: {'Accept-Encoding' => 'gzip'}))
    sds = pg_doc.css('a').map{|a|a['href']}.compact.map{|l|l.match(/https?:\/\/([a-z0-9\-_]+)\.appfolio\.com\/listings\/listings\/.*/)}.compact.map{|m|m[0]}.uniq
    puts "#{page_link} have not so unique listings it seems: #{sds}" if sds.size > 1
    sds
  rescue
    puts "can't catch page #{page_link}"
    []
  end
end

def listing_links(link, total = nil, start = 0)
  site = Nokogiri.HTML(HTTParty.get("#{link}&s=#{start}", timeout: 10, headers: {'Accept-Encoding' => 'gzip'}))
  add_pages = site.css('span.pagelinks a').map{|a|a['href']}.uniq
  puts "#{link}&s=#{start}"
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

