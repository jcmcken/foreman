require 'test_helper'
require 'net'

class DhcpTest < ActiveSupport::TestCase
  setup do
    @lease1 = '{
      "starts": "2014-05-09 11:55:21 UTC",
      "ends": "2214-05-09 12:05:21 UTC",
      "state": "active",
      "mac": "aa:bb:cc:dd:ee:01",
      "subnet": "127.0.0.0/255.0.0.0",
      "ip": "127.0.0.1"
    }'
    @lease1.stubs(:code).returns(200)
    @lease1.stubs(:body).returns(@lease1)
  end

  test "dhcp record should not be created without a mac" do
    assert_raise Net::Validations::Error do
      Net::DHCP::Record.new :hostname => "test", "proxy" => smart_proxies(:one)
    end
  end

  test "dhcp record should not be created without a network" do
    assert_raise Net::Validations::Error do
      Net::DHCP::Record.new :hostname => "test", :mac => "aa:bb:cc:dd:ee:ff", "proxy" => smart_proxies(:one)
    end
  end

  test "dhcp record should not be created without an ip" do
    assert_raise Net::Validations::Error do
      Net::DHCP::Record.new :hostname => "test", :mac => "aa:bb:cc:dd:ee:ff", :network => "127.0.0.0", "proxy" => smart_proxies(:one)
    end
  end

  test "record should have dhcp attributes" do
    record = Net::DHCP::Record.new(:hostname => "test", :mac => "aa:bb:cc:dd:ee:ff",
                                 :network => "127.0.0.0", :ip => "127.0.0.1", "proxy" => smart_proxies(:one))
    assert_equal({:hostname => "test", :mac => "aa:bb:cc:dd:ee:ff",:network => "127.0.0.0", :ip => "127.0.0.1"}, record.send(:attrs))
  end

  test "record should be equal if their attrs are the same" do
    record1 = Net::DHCP::Record.new(:hostname => "test", :mac => "aa:bb:cc:dd:ee:ff",
                                 :network => "127.0.0.0", :ip => "127.0.0.1", "proxy" => smart_proxies(:one))
    record2 = Net::DHCP::Record.new(:hostname => "test", :mac => "aa:bb:cc:dd:ee:ff",
                                 :network => "127.0.0.0", :ip => "127.0.0.1", "proxy" => smart_proxies(:one))
    assert_equal record1, record2
  end

  test "record should be equal if one record has no hostname" do
    record1 = Net::DHCP::Record.new(:mac => "aa:bb:cc:dd:ee:ff",
                                    :network => "127.0.0.0", :ip => "127.0.0.1", "proxy" => smart_proxies(:one))
    record2 = Net::DHCP::Record.new(:hostname => "test", :mac => "aa:bb:cc:dd:ee:ff",
                                    :network => "127.0.0.0", :ip => "127.0.0.1", "proxy" => smart_proxies(:one))
    assert_equal record1, record2
    assert_equal record2, record1
  end

  test "record should not be equal if their attrs are not the same" do
    record1 = Net::DHCP::Record.new(:hostname => "test1", :mac => "aa:bb:cc:dd:ee:ff",
                                    :network => "127.0.0.0", :ip => "127.0.0.1", "proxy" => smart_proxies(:one))
    record2 = Net::DHCP::Record.new(:hostname => "test2", :mac => "aa:bb:cc:dd:ee:ff",
                                    :network => "127.0.0.0", :ip => "127.0.0.1", "proxy" => smart_proxies(:one))
    refute_equal record1, record2
  end

  test "conflicts should be detected for mismatched records" do
    proxy_lease = {"starts"=>"2014-05-09 11:55:21 UTC", "ends"=>"2014-05-09 12:05:21 UTC", "state"=>"active", "mac"=>"aa:bb:cc:dd:ee:ff", "subnet"=>"127.0.0.0/255.0.0.0", "ip"=>"127.0.0.1"}
    ProxyAPI::Resource.any_instance.stubs(:get).returns("")
    ProxyAPI::Resource.any_instance.stubs(:parse).returns(proxy_lease)
    record1 = Net::DHCP::Record.new(:hostname => "test1", :mac => "aa:bb:cc:dd:ee:ff",
                                    :network => "127.0.0.0", :ip => "127.0.0.2",
                                    "proxy" => subnets(:one).dhcp_proxy)
    assert record1.conflicts.present?
  end

  test "conflicts should be not detected for records with no hostname" do
    proxy_lease = {"starts"=>"2014-05-09 11:55:21 UTC", "ends"=>"2014-05-09 12:05:21 UTC", "state"=>"active", "mac"=>"aa:bb:cc:dd:ee:ff", "subnet"=>"127.0.0.0/255.0.0.0", "ip"=>"127.0.0.1"}
    ProxyAPI::Resource.any_instance.stubs(:get).returns("")
    ProxyAPI::Resource.any_instance.stubs(:parse).returns(proxy_lease)
    record1 = Net::DHCP::Record.new(:hostname => "test1", :mac => "aa:bb:cc:dd:ee:ff",
                                    :network => "127.0.0.0", :ip => "127.0.0.1",
                                    "proxy" => subnets(:one).dhcp_proxy)
    assert record1.conflicts.empty?
  end

  test "dhcp record validation should return false when proxy returns nil" do
    ProxyAPI::DHCP.any_instance.stubs(:record).returns(nil)
    record1 = Net::DHCP::Record.new(:hostname => "test1", :mac => "aa:bb:cc:dd:ee:ff",
                                    :network => "127.0.0.0", :ip => "127.0.0.1",
                                    "proxy" => subnets(:one).dhcp_proxy)
    refute record1.valid?
  end

  test "dhcp record must not validate when there is IP conflict" do
    ProxyAPI::Resource.any_instance.stubs(:get).with("127.0.0.0/aa:bb:cc:dd:ee:01").returns(@lease1)
    ProxyAPI::Resource.any_instance.stubs(:get).with("127.0.0.0/127.0.0.1").returns(@lease1)
    ProxyAPI::Resource.any_instance.stubs(:get).with("127.0.0.0/aa:bb:cc:dd:ee:02").raises(RestClient::ResourceNotFound, 'Record not found')
    record1 = Net::DHCP::Record.new(:hostname => "discovered_host1", :mac => "aa:bb:cc:dd:ee:02",
                                    :network => "127.0.0.0", :ip => "127.0.0.1",
                                    "proxy" => subnets(:one).dhcp_proxy)
    refute record1.conflicts.empty?
    refute record1.valid?
  end

  test "dhcp record must not validate when there is MAC conflict" do
    ProxyAPI::Resource.any_instance.stubs(:get).with("127.0.0.0/aa:bb:cc:dd:ee:01").returns(@lease1)
    ProxyAPI::Resource.any_instance.stubs(:get).with("127.0.0.0/127.0.0.1").returns(@lease1)
    ProxyAPI::Resource.any_instance.stubs(:get).with("127.0.0.0/127.0.0.2").raises(RestClient::ResourceNotFound, 'Record not found')
    record1 = Net::DHCP::Record.new(:hostname => "discovered_host1", :mac => "aa:bb:cc:dd:ee:01",
                                    :network => "127.0.0.0", :ip => "127.0.0.2",
                                    "proxy" => subnets(:one).dhcp_proxy)
    refute record1.conflicts.empty?
    refute record1.valid?
  end

  test "dhcp record must validate with multiple leases with same MAC" do
    @lease2 = '{
      "starts": "2014-05-09 11:55:21 UTC",
      "ends": "2214-05-09 12:05:21 UTC",
      "state": "active",
      "mac": "aa:bb:cc:dd:ee:01",
      "subnet": "127.0.0.0/255.0.0.0",
      "ip": "127.0.0.2"
    }'
    @lease2.stubs(:code).returns(200)
    @lease2.stubs(:body).returns(@lease2)
    ProxyAPI::Resource.any_instance.stubs(:get).with("127.0.0.0/aa:bb:cc:dd:ee:01").returns(@lease2)
    ProxyAPI::Resource.any_instance.stubs(:get).with("127.0.0.0/127.0.0.1").returns(@lease1)
    ProxyAPI::Resource.any_instance.stubs(:get).with("127.0.0.0/127.0.0.2").returns(@lease2)
    record1 = Net::DHCP::Record.new(:hostname => "discovered_host1", :mac => "aa:bb:cc:dd:ee:01",
                                    :network => "127.0.0.0", :ip => "127.0.0.2",
                                    "proxy" => subnets(:one).dhcp_proxy)
    assert record1.conflicts.empty?
    assert record1.valid?
  end
end
