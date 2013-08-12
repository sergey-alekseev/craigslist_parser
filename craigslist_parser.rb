require './core_ext/object/blank'
require 'nokogiri'
require 'open-uri'
require 'parallel'
require 'httparty'
require 'csv'

class CraigslistParser
  ANONYMIZED_CRAIGLIST_EMAIL_REGEX = /([-a-z0-9.]+@hous\.craigslist\.org)/i
  SHORT_EMAIL_REGEX = /([-a-z0-9.]+@[-a-z0-9.]+[a-z]{2,})/i
  EMAIL_REGEX =  /^(|(([A-Za-z0-9]+_+)|([A-Za-z0-9]+\-+)|([A-Za-z0-9]+\.+)|([A-Za-z0-9]+\++))*[A-Za-z0-9]+@((\w+\-+)|(\w+\.))*\w{1,63}\.[a-zA-Z]{2,6})$/i
  PHONE_REGEX = /^((\([\d]+\).*)|(.*\([\d.]{5,}\))|([\d.\- \(\)\/]+\((fax|office)\))?|([\d.\- \(\)\/]{10,}.*)|([\d\-]{8,}.*)|(Joey Gonzalez Cell \(fax\)))$/

  def self.get_main_page_html
    headers = { 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/27.0.1453.116 Safari/537.36',
                'Connection' => 'keep-alive',
                'Accept-Encoding' => 'gzip' }
    cg = HTTParty.get('http://www.craigslist.org/about/sites', headers: headers)
    Nokogiri.HTML(cg)
  end

  def self.all_us_and_ca_sites_links
    get_main_page_html.css('div.colmask')[0..1].map { |d| d.css('a').map { |a| a['href'] } }.flatten.uniq
  end

  def self.parse_contact_infos(provider, sanitize = true)
    c_links = Parallel.map(all_us_and_ca_sites_links, in_processes: 4) do |s|
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
    infos = infos.map{|i|sanitize_info(i)}.compact if sanitize
    write_csv(infos, "craigslist_#{provider}_contact_infos")
  end

  def self.parse_emails(provider)
    emails = Parallel.map(all_us_and_ca_sites_links, in_processes: 4) do |site_link|
      begin
        puts "emails for site #{site_link} ..."
        emails_on_page(site_link, provider)
      rescue => e
        puts e.backtrace
      end
    write_csv(emails, "craigslist_#{provider}_emails")
    end.flatten.reject { |e| e.blank? || e.match(ANONYMIZED_CRAIGLIST_EMAIL_REGEX) }.map(&:downcase).uniq.sort
  end

  def self.write_csv(infos, filename)
    puts infos.inspect
    csv_string = CSV.generate do |csv|
      infos.each { |info| csv << [info] }
    end
    File.open("#{filename}.csv",'w') { |f| f.write(csv_string) }
  end

  def self.emails_on_page(site_link, provider)
    Parallel.map(all_links_from_site(site_link, provider), threads: 20) do |link|
      puts "emails for link #{link} ..."
      g = HTTParty.get(link, no_follow: true) rescue nil
      Nokogiri.HTML(g).inner_html.scan(SHORT_EMAIL_REGEX).flatten.uniq if g.present?
    end.flatten.uniq
  end

  def self.all_links_from_site(link, provider)
    listing_links(link + "/search/apa?query=#{provider}").map { |l| l.start_with?('http') ? l : (link + l) }
  end

  def self.sanitize_info(nfo)
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

  def self.listing_links(link, total = nil, start = 0)
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

  protected
    def self.contact_info(provider, link)
      raise "Not implemented"
    end

    def self.contact_links(link)
      raise "Not implemented"
    end
end

CraigslistParser.parse_emails('buildium')
# CraigslistParser.parse_emails('appfolio')
