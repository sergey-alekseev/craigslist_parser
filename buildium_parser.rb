require './craigslist_parser'

class BuildiumParser < CraigslistParser
  def self.contact_info(link)
    g = HTTParty.get(link, no_follow: true) rescue nil # in case when 'contacts' page doesn't exist
    return nil if g.nil?
    nfo = Nokogiri.HTML(g).at_css('#_ctl0_contentPlaceHolderBody_ucSideBox_lblBody').inner_html.split('<br>')
    nfo.delete_at(1)
    nfo.unshift(link)
    nfo
  end

  def self.contact_links(link)
    Parallel.map(all_links_from_site(link, 'buildium'), threads: 20) do |l|
      buildium_subdomains(l)
    end.flatten.uniq.map{|sd|"https://#{sd}.managebuilding.com/Resident/PublicPages/ContactUs.aspx"}
  end

  def self.buildium_subdomains(page_link)
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
end

BuildiumParser.parse_contact_infos('buildium')
