require './core_ext/hash/keys'
require 'httparty'
require 'aws-sdk'
require 'logger'

class Proxy
  include HTTParty

  CONFIG = YAML.load(File.read('proxy.yml')).symbolize_keys

  def self.rotate_ip
    logger = Logger.new(STDOUT)
    ec2 = AWS::EC2.new(CONFIG[:credentials]).regions['us-west-1']

    client = ec2.client.with_options(CONFIG[:credentials])

    result = client.describe_instances(instance_ids: [CONFIG[:instance]])

    if result[:reservation_set][0][:instances_set][0][:network_interface_set][0][:association][:ip_owner_id] == "amazon"
      logger.debug "[Proxy] There is no Public IP. Allocating."

      old_ip = nil

      if ec2.elastic_ips.count > 0
        # First IP without association
        new_ip = ec2.elastic_ips.find {|ip| !ip.associated? }.to_s
      else
        # Allocating new IP
        result = client.allocate_address()
        new_ip = result[:public_ip]
      end

    else
      old_ip = result[:reservation_set][0][:instances_set][0][:network_interface_set][0][:association][:public_ip]

      logger.debug "[Proxy] releasing old IP: #{old_ip}"

      begin
        client.disassociate_address(public_ip: old_ip)
      rescue => e
        logger.error "[Proxy] Error #{e.message}"
      end

      begin
        allocation_id = ec2.elastic_ips[old_ip].allocation_id
        client.release_address(allocation_id: allocation_id)
      rescue => e
        logger.error "[Proxy] Error #{e.message}"
      end

      if new_ip = ec2.elastic_ips.find {|ip| !ip.associated? }
        new_ip = new_ip.to_s
      else
        result = client.allocate_address()
        new_ip = result[:public_ip]
      end

    end

    logger.debug "[Proxy] new IP: #{new_ip}"

    result = client.associate_address(
          :instance_id         => CONFIG[:instance],
          :public_ip           => new_ip,
          :allow_reassociation => true
        )

    if association_id = result[:association_id]
      logger.debug "[Proxy] Association is done: #{association_id}"
    else
      logger.warning "[Proxy] Association was finished unsuccessfully"
    end

    if new_ip
      self.http_proxy new_ip, CONFIG[:port], CONFIG[:user], CONFIG[:password]
    end
  rescue => e
    logger.error "[Proxy] #{e.message}"
  end
end
