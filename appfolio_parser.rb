require './craigslist_parser'

class AppfolioParser < CraigslistParser
  def self.contact_info(link)
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

  def self.contact_links(link)
    Parallel.map(all_links_from_site(link, 'appfolio'), threads: 20) do |l|
      listings(l)
    end.flatten.uniq
  end

  def self.listings(page_link)
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
end

AppfolioParser.parse_contact_infos('appfolio', false)
