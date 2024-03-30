require "test_helper"

class RelationTest < ActiveSupport::TestCase
  def test_from_xml_no_id
    noid = "<osm><relation version='12' changeset='23' /></osm>"
    assert_nothing_raised do
      Relation.from_xml(noid, :create => true)
    end
    message = assert_raise(OSM::APIBadXMLError) do
      Relation.from_xml(noid, :create => false)
    end
    assert_match(/ID is required when updating/, message.message)
  end

  def test_from_xml_no_changeset_id
    nocs = "<osm><relation id='123' version='12' /></osm>"
    message_create = assert_raise(OSM::APIBadXMLError) do
      Relation.from_xml(nocs, :create => true)
    end
    assert_match(/Changeset id is missing/, message_create.message)
    message_update = assert_raise(OSM::APIBadXMLError) do
      Relation.from_xml(nocs, :create => false)
    end
    assert_match(/Changeset id is missing/, message_update.message)
  end

  def test_from_xml_no_version
    no_version = "<osm><relation id='123' changeset='23' /></osm>"
    assert_nothing_raised do
      Relation.from_xml(no_version, :create => true)
    end
    message_update = assert_raise(OSM::APIBadXMLError) do
      Relation.from_xml(no_version, :create => false)
    end
    assert_match(/Version is required when updating/, message_update.message)
  end

  def test_from_xml_id_zero
    id_list = ["", "0", "00", "0.0", "a"]
    id_list.each do |id|
      zero_id = "<osm><relation id='#{id}' changeset='332' version='23' /></osm>"
      assert_nothing_raised do
        Relation.from_xml(zero_id, :create => true)
      end
      message_update = assert_raise(OSM::APIBadUserInput) do
        Relation.from_xml(zero_id, :create => false)
      end
      assert_match(/ID of relation cannot be zero when updating/, message_update.message)
    end
  end

  def test_from_xml_no_text
    no_text = ""
    message_create = assert_raise(OSM::APIBadXMLError) do
      Relation.from_xml(no_text, :create => true)
    end
    assert_match(/Must specify a string with one or more characters/, message_create.message)
    message_update = assert_raise(OSM::APIBadXMLError) do
      Relation.from_xml(no_text, :create => false)
    end
    assert_match(/Must specify a string with one or more characters/, message_update.message)
  end

  def test_from_xml_no_k_v
    nokv = "<osm><relation id='23' changeset='23' version='23'><tag /></relation></osm>"
    message_create = assert_raise(OSM::APIBadXMLError) do
      Relation.from_xml(nokv, :create => true)
    end
    assert_match(/tag is missing key/, message_create.message)
    message_update = assert_raise(OSM::APIBadXMLError) do
      Relation.from_xml(nokv, :create => false)
    end
    assert_match(/tag is missing key/, message_update.message)
  end

  def test_from_xml_no_v
    no_v = "<osm><relation id='23' changeset='23' version='23'><tag k='key' /></relation></osm>"
    message_create = assert_raise(OSM::APIBadXMLError) do
      Relation.from_xml(no_v, :create => true)
    end
    assert_match(/tag is missing value/, message_create.message)
    message_update = assert_raise(OSM::APIBadXMLError) do
      Relation.from_xml(no_v, :create => false)
    end
    assert_match(/tag is missing value/, message_update.message)
  end

  def test_from_xml_duplicate_k
    dupk = "<osm><relation id='23' changeset='23' version='23'><tag k='dup' v='test'/><tag k='dup' v='tester'/></relation></osm>"
    message_create = assert_raise(OSM::APIDuplicateTagsError) do
      Relation.from_xml(dupk, :create => true)
    end
    assert_equal "Element relation/ has duplicate tags with key dup", message_create.message
    message_update = assert_raise(OSM::APIDuplicateTagsError) do
      Relation.from_xml(dupk, :create => false)
    end
    assert_equal "Element relation/23 has duplicate tags with key dup", message_update.message
  end

  def test_relation_members
    relation = create(:relation)
    node = create(:node)
    way = create(:way)
    other_relation = create(:relation)
    create(:relation_member, :relation => relation, :member => node, :member_role => "some node")
    create(:relation_member, :relation => relation, :member => way, :member_role => "some way")
    create(:relation_member, :relation => relation, :member => other_relation, :member_role => "some relation")

    members = Relation.find(relation.id).relation_members
    assert_equal 3, members.count
    assert_equal "some node", members[0].member_role
    assert_equal "Node", members[0].member_type
    assert_equal node.id, members[0].member_id
    assert_equal "some way", members[1].member_role
    assert_equal "Way", members[1].member_type
    assert_equal way.id, members[1].member_id
    assert_equal "some relation", members[2].member_role
    assert_equal "Relation", members[2].member_type
    assert_equal other_relation.id, members[2].member_id
  end

  def test_relations
    relation = create(:relation)
    node = create(:node)
    way = create(:way)
    other_relation = create(:relation)
    create(:relation_member, :relation => relation, :member => node, :member_role => "some node")
    create(:relation_member, :relation => relation, :member => way, :member_role => "some way")
    create(:relation_member, :relation => relation, :member => other_relation, :member_role => "some relation")

    members = Relation.find(relation.id).members
    assert_equal 3, members.count
    assert_equal ["Node", node.id, "some node"], members[0]
    assert_equal ["Way", way.id, "some way"], members[1]
    assert_equal ["Relation", other_relation.id, "some relation"], members[2]
  end

  def test_relation_tags
    relation = create(:relation)
    taglist = create_list(:relation_tag, 2, :relation => relation)

    tags = Relation.find(relation.id).relation_tags.order(:k)
    assert_equal taglist.count, tags.count
    taglist.sort_by!(&:k).each_index do |i|
      assert_equal taglist[i].k, tags[i].k
      assert_equal taglist[i].v, tags[i].v
    end
  end

  def test_tags
    relation = create(:relation)
    taglist = create_list(:relation_tag, 2, :relation => relation)

    tags = Relation.find(relation.id).tags
    assert_equal taglist.count, tags.count
    taglist.each do |tag|
      assert_equal tag.v, tags[tag.k]
    end
  end

  def test_containing_relation_members
    relation = create(:relation)
    super_relation = create(:relation)
    create(:relation_member, :relation => super_relation, :member => relation)

    crm = Relation.find(relation.id).containing_relation_members.order(:relation_id)
    #    assert_equal 1, crm.size
    assert_equal super_relation.id, crm.first.relation_id
    assert_equal "Relation", crm.first.member_type
    assert_equal relation.id, crm.first.member_id
    assert_equal super_relation.id, crm.first.relation.id
  end

  def test_containing_relations
    relation = create(:relation)
    super_relation = create(:relation)
    create(:relation_member, :relation => super_relation, :member => relation)

    cr = Relation.find(relation.id).containing_relations.order(:id)
    assert_equal 1, cr.size
    assert_equal super_relation.id, cr.first.id
  end

  def test_update_changeset_bbox_any_relation
    relation = create(:relation)
    super_relation = create(:relation)
    node = create(:node, :longitude => 116, :latitude => 39)
    create(:relation_member, :relation => super_relation, :member_type => "Relation", :member_id => relation.id)
    node_member = create(:relation_member, :relation => super_relation, :member_type => "Node", :member_id => node.id)
    user = create(:user)
    changeset = create(:changeset, :user => user)
    assert_nil changeset.min_lon
    assert_nil changeset.max_lon
    assert_nil changeset.max_lat
    assert_nil changeset.min_lat
    new_relation = build(:relation, :id => super_relation.id,
                                    :version => super_relation.version,
                                    :changeset => changeset)
    new_relation.add_member node_member.member_type, node_member.member_id, node_member.member_role
    # one member(relation type) was removed, so any_relation flag is expected to be true.
    super_relation.update_from(new_relation, user)

    # changeset updated by node member, representing any_relation flag true.
    assert_equal 116, changeset.min_lon
    assert_equal 116, changeset.max_lon
    assert_equal 39, changeset.min_lat
    assert_equal 39, changeset.max_lat
  end

  def test_changeset_bbox_delete_relation
    orig_relation = create(:relation)
    node1 = create(:node, :longitude => 116, :latitude => 39)
    node2 = create(:node, :longitude => 39, :latitude => 116)
    create(:relation_member, :relation => orig_relation, :member_type => "Node", :member_id => node1.id)
    create(:relation_member, :relation => orig_relation, :member_type => "Node", :member_id => node2.id)
    user = create(:user)
    changeset = create(:changeset, :user => user)
    assert_nil changeset.min_lon
    assert_nil changeset.max_lon
    assert_nil changeset.max_lat
    assert_nil changeset.min_lat

    new_relation = build(:relation, :id => orig_relation.id,
                                    :version => orig_relation.version,
                                    :changeset_id => changeset.id)
    orig_relation.delete_with_history!(new_relation, user)
    changeset.reload
    assert_equal 39, changeset.min_lon
    assert_equal 116, changeset.max_lon
    assert_equal 39, changeset.min_lat
    assert_equal 116, changeset.max_lat
  end

  # Check that the preconditions fail when you are over the defined limit of
  # the maximum number of members in a relation.
  def test_max_members_per_relation_limit
    # Speed up unit test by using a small relation member limit
    with_settings(:max_number_of_relation_members => 20) do
      user = create(:user)
      changeset = create(:changeset, :user => user)
      relation = create(:relation, :changeset => changeset)
      node = create(:node, :longitude => 116, :latitude => 39)
      # Create relation which exceeds the relation member limit by one
      0.upto(Settings.max_number_of_relation_members) do |i|
        create(:relation_member, :relation => relation, :member_type => "Node", :member_id => node.id, :sequence_id => i)
      end

      assert_raise OSM::APITooManyRelationMembersError do
        relation.create_with_history user
      end
    end
  end

  test "raises missing changeset exception when creating" do
    user = create(:user)
    relation = Relation.new
    assert_raises OSM::APIChangesetMissingError do
      relation.create_with_history(user)
    end
  end

  test "raises user-changeset mismatch exception when creating" do
    user = create(:user)
    changeset = create(:changeset)
    relation = Relation.new(:changeset => changeset)
    assert_raises OSM::APIUserChangesetMismatchError do
      relation.create_with_history(user)
    end
  end

  test "raises already closed changeset exception when creating" do
    user = create(:user)
    changeset = create(:changeset, :closed, :user => user)
    relation = Relation.new(:changeset => changeset)
    assert_raises OSM::APIChangesetAlreadyClosedError do
      relation.create_with_history(user)
    end
  end

  test "raises id precondition exception when updating" do
    user = create(:user)
    relation = Relation.new(:id => 23)
    new_relation = Relation.new(:id => 42)
    assert_raises OSM::APIPreconditionFailedError do
      relation.update_from(new_relation, user)
    end
  end

  test "raises version mismatch exception when updating" do
    user = create(:user)
    relation = Relation.new(:id => 42, :version => 7)
    new_relation = Relation.new(:id => 42, :version => 12)
    assert_raises OSM::APIVersionMismatchError do
      relation.update_from(new_relation, user)
    end
  end

  test "raises missing changeset exception when updating" do
    user = create(:user)
    relation = Relation.new(:id => 42, :version => 12)
    new_relation = Relation.new(:id => 42, :version => 12)
    assert_raises OSM::APIChangesetMissingError do
      relation.update_from(new_relation, user)
    end
  end

  test "raises user-changeset mismatch exception when updating" do
    user = create(:user)
    changeset = create(:changeset)
    relation = Relation.new(:id => 42, :version => 12)
    new_relation = Relation.new(:id => 42, :version => 12, :changeset => changeset)
    assert_raises OSM::APIUserChangesetMismatchError do
      relation.update_from(new_relation, user)
    end
  end

  test "raises already closed changeset exception when updating" do
    user = create(:user)
    changeset = create(:changeset, :closed, :user => user)
    relation = Relation.new(:id => 42, :version => 12)
    new_relation = Relation.new(:id => 42, :version => 12, :changeset => changeset)
    assert_raises OSM::APIChangesetAlreadyClosedError do
      relation.update_from(new_relation, user)
    end
  end
end
