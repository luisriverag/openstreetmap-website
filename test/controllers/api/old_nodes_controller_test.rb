require "test_helper"

module Api
  class OldNodesControllerTest < ActionDispatch::IntegrationTest
    #
    # TODO: test history
    #

    ##
    # test all routes which lead to this controller
    def test_routes
      assert_routing(
        { :path => "/api/0.6/node/1/history", :method => :get },
        { :controller => "api/old_nodes", :action => "history", :id => "1" }
      )
      assert_routing(
        { :path => "/api/0.6/node/1/2", :method => :get },
        { :controller => "api/old_nodes", :action => "show", :id => "1", :version => "2" }
      )
      assert_routing(
        { :path => "/api/0.6/node/1/history.json", :method => :get },
        { :controller => "api/old_nodes", :action => "history", :id => "1", :format => "json" }
      )
      assert_routing(
        { :path => "/api/0.6/node/1/2.json", :method => :get },
        { :controller => "api/old_nodes", :action => "show", :id => "1", :version => "2", :format => "json" }
      )
      assert_routing(
        { :path => "/api/0.6/node/1/2/redact", :method => :post },
        { :controller => "api/old_nodes", :action => "redact", :id => "1", :version => "2" }
      )
    end

    ##
    # test the version call by submitting several revisions of a new node
    # to the API and ensuring that later calls to version return the
    # matching versions of the object.
    #
    ##
    # FIXME: Move this test to being an integration test since it spans multiple controllers
    def test_version
      private_user = create(:user, :data_public => false)
      private_node = create(:node, :with_history, :version => 4, :lat => 0, :lon => 0, :changeset => create(:changeset, :user => private_user))
      user = create(:user)
      node = create(:node, :with_history, :version => 4, :lat => 0, :lon => 0, :changeset => create(:changeset, :user => user))
      create_list(:node_tag, 2, :node => node)
      # Ensure that the current tags are propagated to the history too
      propagate_tags(node, node.old_nodes.last)

      ## First try this with a non-public user
      auth_header = bearer_authorization_header private_user

      # setup a simple XML node
      xml_doc = xml_for_node(private_node)
      xml_node = xml_doc.find("//osm/node").first
      nodeid = private_node.id

      # keep a hash of the versions => string, as we'll need something
      # to test against later
      versions = {}

      # save a version for later checking
      versions[xml_node["version"]] = xml_doc.to_s

      # randomly move the node about
      3.times do
        # move the node somewhere else
        xml_node["lat"] = precision(rand - 0.5).to_s
        xml_node["lon"] = precision(rand - 0.5).to_s
        with_controller(NodesController.new) do
          put api_node_path(nodeid), :params => xml_doc.to_s, :headers => auth_header
          assert_response :forbidden, "Should have rejected node update"
          xml_node["version"] = @response.body.to_s
        end
        # save a version for later checking
        versions[xml_node["version"]] = xml_doc.to_s
      end

      # add a bunch of random tags
      3.times do
        xml_tag = XML::Node.new("tag")
        xml_tag["k"] = random_string
        xml_tag["v"] = random_string
        xml_node << xml_tag
        with_controller(NodesController.new) do
          put api_node_path(nodeid), :params => xml_doc.to_s, :headers => auth_header
          assert_response :forbidden,
                          "should have rejected node #{nodeid} (#{@response.body}) with forbidden"
          xml_node["version"] = @response.body.to_s
        end
        # save a version for later checking
        versions[xml_node["version"]] = xml_doc.to_s
      end

      # probably should check that they didn't get written to the database

      ## Now do it with the public user
      auth_header = bearer_authorization_header user

      # setup a simple XML node

      xml_doc = xml_for_node(node)
      xml_node = xml_doc.find("//osm/node").first
      nodeid = node.id

      # keep a hash of the versions => string, as we'll need something
      # to test against later
      versions = {}

      # save a version for later checking
      versions[xml_node["version"]] = xml_doc.to_s

      # randomly move the node about
      3.times do
        # move the node somewhere else
        xml_node["lat"] = precision(rand - 0.5).to_s
        xml_node["lon"] = precision(rand - 0.5).to_s
        with_controller(NodesController.new) do
          put api_node_path(nodeid), :params => xml_doc.to_s, :headers => auth_header
          assert_response :success
          xml_node["version"] = @response.body.to_s
        end
        # save a version for later checking
        versions[xml_node["version"]] = xml_doc.to_s
      end

      # add a bunch of random tags
      3.times do
        xml_tag = XML::Node.new("tag")
        xml_tag["k"] = random_string
        xml_tag["v"] = random_string
        xml_node << xml_tag
        with_controller(NodesController.new) do
          put api_node_path(nodeid), :params => xml_doc.to_s, :headers => auth_header
          assert_response :success,
                          "couldn't update node #{nodeid} (#{@response.body})"
          xml_node["version"] = @response.body.to_s
        end
        # save a version for later checking
        versions[xml_node["version"]] = xml_doc.to_s
      end

      # check all the versions
      versions.each_key do |key|
        get api_old_node_path(nodeid, key.to_i)

        assert_response :success,
                        "couldn't get version #{key.to_i} of node #{nodeid}"

        check_node = Node.from_xml(versions[key])
        api_node = Node.from_xml(@response.body.to_s)

        assert_nodes_are_equal check_node, api_node
      end
    end

    def test_not_found_version
      check_not_found_id_version(70000, 312344)
      check_not_found_id_version(-1, -13)
      check_not_found_id_version(create(:node).id, 24354)
      check_not_found_id_version(24356, create(:node).version)
    end

    ##
    # Test that getting the current version is identical to picking
    # that version with the version URI call.
    def test_current_version
      node = create(:node, :with_history)
      used_node = create(:node, :with_history)
      create(:way_node, :node => used_node)
      node_used_by_relationship = create(:node, :with_history)
      create(:relation_member, :member => node_used_by_relationship)
      node_with_versions = create(:node, :with_history, :version => 4)

      create(:node_tag, :node => node)
      create(:node_tag, :node => used_node)
      create(:node_tag, :node => node_used_by_relationship)
      create(:node_tag, :node => node_with_versions)
      propagate_tags(node, node.old_nodes.last)
      propagate_tags(used_node, used_node.old_nodes.last)
      propagate_tags(node_used_by_relationship, node_used_by_relationship.old_nodes.last)
      propagate_tags(node_with_versions, node_with_versions.old_nodes.last)

      check_current_version(node)
      check_current_version(used_node)
      check_current_version(node_used_by_relationship)
      check_current_version(node_with_versions)
    end

    # Ensure the lat/lon is formatted as a decimal e.g. not 4.0e-05
    def test_lat_lon_xml_format
      old_node = create(:old_node, :latitude => (0.00004 * OldNode::SCALE).to_i, :longitude => (0.00008 * OldNode::SCALE).to_i)

      get api_node_history_path(old_node.node_id)
      assert_match(/lat="0.0000400"/, response.body)
      assert_match(/lon="0.0000800"/, response.body)
    end

    ##
    # test the redaction of an old version of a node, while not being
    # authorised.
    def test_redact_node_unauthorised
      node = create(:node, :with_history, :version => 4)
      node_v3 = node.old_nodes.find_by(:version => 3)

      do_redact_node(node_v3,
                     create(:redaction))
      assert_response :unauthorized, "should need to be authenticated to redact."
    end

    ##
    # test the redaction of an old version of a node, while being
    # authorised as a normal user.
    def test_redact_node_normal_user
      auth_header = bearer_authorization_header

      node = create(:node, :with_history, :version => 4)
      node_v3 = node.old_nodes.find_by(:version => 3)

      do_redact_node(node_v3,
                     create(:redaction),
                     auth_header)
      assert_response :forbidden, "should need to be moderator to redact."
    end

    ##
    # test that, even as moderator, the current version of a node
    # can't be redacted.
    def test_redact_node_current_version
      auth_header = bearer_authorization_header create(:moderator_user)

      node = create(:node, :with_history, :version => 4)
      node_v4 = node.old_nodes.find_by(:version => 4)

      do_redact_node(node_v4,
                     create(:redaction),
                     auth_header)
      assert_response :bad_request, "shouldn't be OK to redact current version as moderator."
    end

    def test_redact_node_by_regular_without_write_redactions_scope
      auth_header = bearer_authorization_header(create(:user), :scopes => %w[read_prefs write_api])
      do_redact_redactable_node(auth_header)
      assert_response :forbidden, "should need to be moderator to redact."
    end

    def test_redact_node_by_regular_with_write_redactions_scope
      auth_header = bearer_authorization_header(create(:user), :scopes => %w[write_redactions])
      do_redact_redactable_node(auth_header)
      assert_response :forbidden, "should need to be moderator to redact."
    end

    def test_redact_node_by_moderator_without_write_redactions_scope
      auth_header = bearer_authorization_header(create(:moderator_user), :scopes => %w[read_prefs write_api])
      do_redact_redactable_node(auth_header)
      assert_response :forbidden, "should need to have write_redactions scope to redact."
    end

    def test_redact_node_by_moderator_with_write_redactions_scope
      auth_header = bearer_authorization_header(create(:moderator_user), :scopes => %w[write_redactions])
      do_redact_redactable_node(auth_header)
      assert_response :success, "should be OK to redact old version as moderator with write_redactions scope."
    end

    ##
    # test that redacted nodes aren't visible, regardless of
    # authorisation except as moderator...
    def test_version_redacted
      node = create(:node, :with_history, :version => 2)
      node_v1 = node.old_nodes.find_by(:version => 1)
      node_v1.redact!(create(:redaction))

      get api_old_node_path(node_v1.node_id, node_v1.version)
      assert_response :forbidden, "Redacted node shouldn't be visible via the version API."

      # not even to a logged-in user
      auth_header = bearer_authorization_header
      get api_old_node_path(node_v1.node_id, node_v1.version), :headers => auth_header
      assert_response :forbidden, "Redacted node shouldn't be visible via the version API, even when logged in."
    end

    ##
    # test that redacted nodes aren't visible in the history
    def test_history_redacted
      node = create(:node, :with_history, :version => 2)
      node_v1 = node.old_nodes.find_by(:version => 1)
      node_v1.redact!(create(:redaction))

      get api_node_history_path(node)
      assert_response :success, "Redaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v1.node_id}'][version='#{node_v1.version}']", 0,
                    "redacted node #{node_v1.node_id} version #{node_v1.version} shouldn't be present in the history."

      # not even to a logged-in user
      auth_header = bearer_authorization_header
      get api_node_history_path(node), :headers => auth_header
      assert_response :success, "Redaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v1.node_id}'][version='#{node_v1.version}']", 0,
                    "redacted node #{node_v1.node_id} version #{node_v1.version} shouldn't be present in the history, even when logged in."
    end

    ##
    # test the redaction of an old version of a node, while being
    # authorised as a moderator.
    def test_redact_node_moderator
      node = create(:node, :with_history, :version => 4)
      node_v3 = node.old_nodes.find_by(:version => 3)
      auth_header = bearer_authorization_header create(:moderator_user)

      do_redact_node(node_v3, create(:redaction), auth_header)
      assert_response :success, "should be OK to redact old version as moderator."

      # check moderator can still see the redacted data, when passing
      # the appropriate flag
      get api_old_node_path(node_v3.node_id, node_v3.version), :headers => auth_header
      assert_response :forbidden, "After redaction, node should be gone for moderator, when flag not passed."
      get api_old_node_path(node_v3.node_id, node_v3.version, :show_redactions => "true"), :headers => auth_header
      assert_response :success, "After redaction, node should not be gone for moderator, when flag passed."

      # and when accessed via history
      get api_node_history_path(node)
      assert_response :success, "Redaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v3.node_id}'][version='#{node_v3.version}']", 0,
                    "node #{node_v3.node_id} version #{node_v3.version} should not be present in the history for moderators when not passing flag."
      get api_node_history_path(node, :show_redactions => "true"), :headers => auth_header
      assert_response :success, "Redaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v3.node_id}'][version='#{node_v3.version}']", 1,
                    "node #{node_v3.node_id} version #{node_v3.version} should still be present in the history for moderators when passing flag."
    end

    # testing that if the moderator drops auth, he can't see the
    # redacted stuff any more.
    def test_redact_node_is_redacted
      node = create(:node, :with_history, :version => 4)
      node_v3 = node.old_nodes.find_by(:version => 3)
      auth_header = bearer_authorization_header create(:moderator_user)

      do_redact_node(node_v3, create(:redaction), auth_header)
      assert_response :success, "should be OK to redact old version as moderator."

      # re-auth as non-moderator
      auth_header = bearer_authorization_header

      # check can't see the redacted data
      get api_old_node_path(node_v3.node_id, node_v3.version), :headers => auth_header
      assert_response :forbidden, "Redacted node shouldn't be visible via the version API."

      # and when accessed via history
      get api_node_history_path(node), :headers => auth_header
      assert_response :success, "Redaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v3.node_id}'][version='#{node_v3.version}']", 0,
                    "redacted node #{node_v3.node_id} version #{node_v3.version} shouldn't be present in the history."
    end

    ##
    # test the unredaction of an old version of a node, while not being
    # authorised.
    def test_unredact_node_unauthorised
      node = create(:node, :with_history, :version => 2)
      node_v1 = node.old_nodes.find_by(:version => 1)
      node_v1.redact!(create(:redaction))

      post node_version_redact_path(node_v1.node_id, node_v1.version)
      assert_response :unauthorized, "should need to be authenticated to unredact."
    end

    ##
    # test the unredaction of an old version of a node, while being
    # authorised as a normal user.
    def test_unredact_node_normal_user
      user = create(:user)
      node = create(:node, :with_history, :version => 2)
      node_v1 = node.old_nodes.find_by(:version => 1)
      node_v1.redact!(create(:redaction))

      auth_header = bearer_authorization_header user

      post node_version_redact_path(node_v1.node_id, node_v1.version), :headers => auth_header
      assert_response :forbidden, "should need to be moderator to unredact."
    end

    ##
    # test the unredaction of an old version of a node, while being
    # authorised as a moderator.
    def test_unredact_node_moderator
      moderator_user = create(:moderator_user)
      node = create(:node, :with_history, :version => 2)
      node_v1 = node.old_nodes.find_by(:version => 1)
      node_v1.redact!(create(:redaction))

      auth_header = bearer_authorization_header moderator_user

      post node_version_redact_path(node_v1.node_id, node_v1.version), :headers => auth_header
      assert_response :success, "should be OK to unredact old version as moderator."

      # check moderator can now see the redacted data, when not
      # passing the aspecial flag
      get api_old_node_path(node_v1.node_id, node_v1.version), :headers => auth_header
      assert_response :success, "After unredaction, node should not be gone for moderator."

      # and when accessed via history
      get api_node_history_path(node)
      assert_response :success, "Unredaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v1.node_id}'][version='#{node_v1.version}']", 1,
                    "node #{node_v1.node_id} version #{node_v1.version} should now be present in the history for moderators without passing flag."

      auth_header = bearer_authorization_header

      # check normal user can now see the redacted data
      get api_old_node_path(node_v1.node_id, node_v1.version), :headers => auth_header
      assert_response :success, "After unredaction, node should be visible to normal users."

      # and when accessed via history
      get api_node_history_path(node)
      assert_response :success, "Unredaction shouldn't have stopped history working."
      assert_select "osm node[id='#{node_v1.node_id}'][version='#{node_v1.version}']", 1,
                    "node #{node_v1.node_id} version #{node_v1.version} should now be present in the history for normal users without passing flag."
    end

    private

    def do_redact_redactable_node(headers = {})
      node = create(:node, :with_history, :version => 4)
      node_v3 = node.old_nodes.find_by(:version => 3)
      do_redact_node(node_v3, create(:redaction), headers)
    end

    def do_redact_node(node, redaction, headers = {})
      get api_old_node_path(node.node_id, node.version), :headers => headers
      assert_response :success, "should be able to get version #{node.version} of node #{node.node_id}."

      # now redact it
      post node_version_redact_path(node.node_id, node.version), :params => { :redaction => redaction.id }, :headers => headers
    end

    def check_current_version(node_id)
      # get the current version of the node
      current_node = with_controller(NodesController.new) do
        get api_node_path(node_id)
        assert_response :success, "cant get current node #{node_id}"
        Node.from_xml(@response.body)
      end
      assert_not_nil current_node, "getting node #{node_id} returned nil"

      # get the "old" version of the node from the old_node interface
      get api_old_node_path(node_id, current_node.version)
      assert_response :success, "cant get old node #{node_id}, v#{current_node.version}"
      old_node = Node.from_xml(@response.body)

      # check the nodes are the same
      assert_nodes_are_equal current_node, old_node
    end

    def check_not_found_id_version(id, version)
      get api_old_node_path(id, version)
      assert_response :not_found
    rescue ActionController::UrlGenerationError => e
      assert_match(/No route matches/, e.to_s)
    end

    ##
    # returns a 16 character long string with some nasty characters in it.
    # this ought to stress-test the tag handling as well as the versioning.
    def random_string
      letters = [["!", '"', "$", "&", ";", "@"],
                 ("a".."z").to_a,
                 ("A".."Z").to_a,
                 ("0".."9").to_a].flatten
      (1..16).map { letters[rand(letters.length)] }.join
    end

    ##
    # truncate a floating point number to the scale that it is stored in
    # the database. otherwise rounding errors can produce failing unit
    # tests when they shouldn't.
    def precision(f)
      (f * GeoRecord::SCALE).round.to_f / GeoRecord::SCALE
    end

    def propagate_tags(node, old_node)
      node.tags.each do |k, v|
        create(:old_node_tag, :old_node => old_node, :k => k, :v => v)
      end
    end
  end
end
