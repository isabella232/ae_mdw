defmodule Integration.AeMdwWeb.NameControllerTest do
  use AeMdwWeb.ConnCase

  alias :aeser_api_encoder, as: Enc

  alias AeMdw.Db.Format
  alias AeMdw.Db.Model
  alias AeMdw.Db.Name
  alias AeMdw.Db.Util
  alias AeMdw.Error.Input, as: ErrInput
  alias AeMdw.Validate
  alias AeMdwWeb.TestUtil

  require Model

  @moduletag :integration

  @default_limit 10

  describe "active_names_v1" do
    test "it get active names backwards without any filters", %{conn: conn} do
      assert %{"data" => names, "next" => next} =
               conn |> get("/names/active") |> json_response(200)

      expirations =
        names
        |> Enum.map(fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)
        |> Enum.reverse()

      assert length(names) <= @default_limit
      assert ^expirations = Enum.sort(expirations)

      assert %{"data" => next_names, "prev" => prev_names} =
               conn |> get(next) |> json_response(200)

      if next do
        next_expirations =
          next_names
          |> Enum.map(fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)
          |> Enum.reverse()

        assert length(next_names) <= @default_limit
        assert ^next_expirations = Enum.sort(next_expirations)
        assert Enum.at(expirations, @default_limit - 1) >= Enum.at(next_expirations, 0)

        assert %{"data" => ^names} = conn |> get(prev_names) |> json_response(200)
      end
    end

    test "get active names forward with limit=4", %{conn: conn} do
      limit = 4

      assert %{"data" => names, "next" => next} =
               conn
               |> get("/names/active", direction: "forward", limit: limit)
               |> json_response(200)

      expirations =
        Enum.map(names, fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)

      assert length(names) <= limit
      assert ^expirations = Enum.sort(expirations)

      if next do
        assert %{"data" => next_names, "prev" => prev_names} =
                 conn |> get(next) |> json_response(200)

        next_expirations =
          Enum.map(next_names, fn %{"info" => %{"expire_height" => expire_height}} ->
            expire_height
          end)

        assert length(next_names) <= 4
        assert ^next_expirations = Enum.sort(next_expirations)
        assert Enum.at(expirations, limit - 1) <= Enum.at(next_expirations, 0)

        assert %{"data" => ^names} = conn |> get(prev_names) |> json_response(200)
      end
    end

    test "get active names with parameters by=name, direction=forward and limit=3", %{conn: conn} do
      by = "name"
      direction = "forward"
      limit = 3

      assert %{"data" => names} =
               conn
               |> get("/names/active", by: by, direction: direction, limit: limit)
               |> json_response(200)

      plain_names = Enum.map(names, fn %{"name" => name} -> name end)

      assert length(names) <= limit
      assert ^plain_names = Enum.sort(plain_names)
    end

    test "renders error when parameter by is invalid", %{conn: conn} do
      by = "invalid_by"
      error_msg = "invalid query: by=#{by}"

      assert %{"error" => ^error_msg} = conn |> get("/names/active", by: by) |> json_response(400)
    end

    test "renders error when parameter direction is invalid", %{conn: conn} do
      by = "name"
      direction = "invalid_direction"
      error_msg = "invalid direction: #{direction}"

      assert %{"error" => ^error_msg} =
               conn |> get("/names/active", by: by, direction: direction) |> json_response(400)
    end

    test "it returns valid active names on a given range", %{conn: conn} do
      first = 100_000
      last = 500_000

      assert %{"data" => data} =
               conn
               |> get("/names/active/gen/#{first}-#{last}")
               |> json_response(200)

      assert Enum.all?(data, fn %{"info" => %{"expire_height" => kbi}} ->
               first <= kbi and kbi <= last
             end)
    end

    test "it returns valid active names on a given range, in reverse order", %{conn: conn} do
      first = 4_000_000
      last = 100_000

      assert %{"data" => data, "next" => next} =
               conn
               |> get("/names/active/gen/#{first}-#{last}")
               |> json_response(200)

      assert Enum.all?(data, fn %{"info" => %{"expire_height" => kbi}} ->
               last <= kbi and kbi <= first
             end)

      kbis =
        data |> Enum.map(fn %{"info" => %{"expire_height" => kbi}} -> kbi end) |> Enum.reverse()

      assert Enum.sort(kbis) == kbis
    end
  end

  describe "inactive_names_v1" do
    test "get inactive names with default limit", %{conn: conn} do
      assert %{"data" => names, "next" => next} =
               conn |> get("/names/inactive") |> json_response(200)

      expirations =
        names
        |> Enum.map(fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)
        |> Enum.reverse()

      assert @default_limit = length(names)
      assert ^expirations = Enum.sort(expirations)

      assert %{"data" => next_names, "prev" => prev_names} =
               conn |> get(next) |> json_response(200)

      next_expirations =
        next_names
        |> Enum.map(fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)
        |> Enum.reverse()

      assert @default_limit = length(next_names)
      assert ^next_expirations = Enum.sort(next_expirations)
      assert Enum.at(expirations, @default_limit - 1) >= Enum.at(next_expirations, 0)

      assert %{"data" => ^names} = conn |> get(prev_names) |> json_response(200)
    end

    test "get inactive names forward with limit=6", %{conn: conn} do
      limit = 4

      assert %{"data" => names, "next" => next} =
               conn
               |> get("/names/inactive", direction: "forward", limit: limit)
               |> json_response(200)

      expirations =
        Enum.map(names, fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)

      assert ^limit = length(names)
      assert ^expirations = Enum.sort(expirations)

      assert %{"data" => next_names, "prev" => prev_names} =
               conn |> get(next) |> json_response(200)

      next_expirations =
        Enum.map(next_names, fn %{"info" => %{"expire_height" => expire_height}} ->
          expire_height
        end)

      assert ^limit = length(next_names)
      assert ^next_expirations = Enum.sort(next_expirations)
      assert Enum.at(expirations, limit - 1) <= Enum.at(next_expirations, 0)

      assert %{"data" => ^names} = conn |> get(prev_names) |> json_response(200)
    end

    test "get inactive names with parameters by=name, direction=forward and limit=4", %{
      conn: conn
    } do
      by = "name"
      direction = "forward"
      limit = 4

      assert %{"data" => names} =
               conn
               |> get("/names/inactive", by: by, direction: direction, limit: limit)
               |> json_response(200)

      plain_names = Enum.map(names, fn %{"name" => name} -> name end)

      assert ^limit = length(names)
      assert ^plain_names = Enum.sort(plain_names)
    end

    test "renders error when parameter by is invalid", %{conn: conn} do
      by = "invalid_by"
      error_msg = "invalid query: by=#{by}"

      assert %{"error" => ^error_msg} =
               conn |> get("/names/inactive?by=#{by}") |> json_response(400)
    end

    test "renders error when parameter direction is invalid", %{conn: conn} do
      by = "name"
      direction = "invalid_direction"
      error_msg = "invalid direction: #{direction}"

      assert %{"error" => ^error_msg} =
               conn |> get("/names/inactive", by: by, direction: direction) |> json_response(400)
    end

    test "it returns valid names on a given range", %{conn: conn} do
      first = 100_000
      last = 500_000

      assert %{"data" => data, "next" => next} =
               conn
               |> get("/names/inactive/gen/#{first}-#{last}")
               |> json_response(200)

      assert Enum.all?(data, fn %{"info" => %{"expire_height" => kbi}} ->
               first <= kbi and kbi <= last
             end)

      assert @default_limit = length(data)

      assert %{"data" => data2} =
               conn
               |> get(next)
               |> json_response(200)

      assert @default_limit = length(data2)

      assert Enum.all?(data2, fn %{"info" => %{"expire_height" => kbi}} ->
               first <= kbi and kbi <= last
             end)
    end

    test "it returns valid names on a given range, in reverse order", %{conn: conn} do
      first = 500_000
      last = 100_000

      assert %{"data" => data, "next" => next} =
               conn
               |> get("/names/inactive/gen/#{first}-#{last}")
               |> json_response(200)

      assert Enum.all?(data, fn %{"info" => %{"expire_height" => kbi}} ->
               last <= kbi and kbi <= first
             end)

      assert @default_limit = length(data)

      kbis =
        data |> Enum.map(fn %{"info" => %{"expire_height" => kbi}} -> kbi end) |> Enum.reverse()

      assert Enum.sort(kbis) == kbis
    end
  end

  describe "inactive_names" do
  end

  describe "auctions" do
    test "get auctions with default limit", %{conn: conn} do
      assert %{"data" => auctions} = conn |> get("/names/auctions") |> json_response(200)

      expirations =
        auctions
        |> Enum.map(fn %{"info" => %{"auction_end" => expire}} -> expire end)
        |> Enum.reverse()

      assert length(auctions) <= @default_limit
      assert ^expirations = Enum.sort(expirations)
    end

    test "get auctions with limit=2", %{conn: conn} do
      limit = 2

      assert %{"data" => auctions} =
               conn |> get("/names/auctions", limit: limit) |> json_response(200)

      names =
        Enum.map(auctions, fn %{"name" => plain_name, "info" => %{"auction_end" => auction_end}} ->
          {plain_name, auction_end}
        end)

      assert length(auctions) <= limit
      assert Enum.all?(names, fn {plain_name, _auction_end} -> plain_name != "" end)
      assert ^names = Enum.sort_by(names, fn {_name, expires} -> expires end, :desc)
    end

    test "get auctions with parameters by=expiration, direction=forward and limit=3", %{
      conn: conn
    } do
      limit = 3
      by = "expiration"
      direction = "forward"

      assert %{"data" => auctions} =
               conn
               |> get("/names/auctions", by: by, direction: direction, limit: limit)
               |> json_response(200)

      expires = Enum.map(auctions, fn %{"info" => %{"auction_end" => expires}} -> expires end)

      assert length(auctions) <= limit
      assert ^expires = Enum.sort(expires)
    end

    test "get auctions with parameters by=name, direction=backward and limit=3", %{
      conn: conn
    } do
      limit = 3
      by = "name"
      direction = "backward"

      assert %{"data" => auctions} =
               conn
               |> get("/names/auctions", by: by, direction: direction, limit: limit)
               |> json_response(200)

      plain_names =
        auctions |> Enum.map(fn %{"name" => plain_name} -> plain_name end) |> Enum.reverse()

      assert length(auctions) <= limit
      assert ^plain_names = Enum.sort(plain_names)
    end

    test "renders error when parameter by is invalid", %{conn: conn} do
      by = "invalid_by"
      error_msg = "invalid query: by=#{by}"

      %{"error" => ^error_msg} = conn |> get("/names/auctions", by: by) |> json_response(400)
    end

    test "renders error when parameter direction is invalid", %{conn: conn} do
      by = "name"
      direction = "invalid_direction"
      error_msg = "invalid direction: #{direction}"

      %{"error" => ^error_msg} =
        conn |> get("/names/auctions", by: by, direction: direction) |> json_response(400)
    end
  end

  describe "names_v1" do
    test "get active and inactive names, except those in auction, with default limit", %{
      conn: conn
    } do
      assert %{"data" => names, "next" => next} = conn |> get("/names") |> json_response(200)

      expirations =
        names
        |> Enum.map(fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)
        |> Enum.reverse()

      assert @default_limit = length(names)
      assert ^expirations = Enum.sort(expirations)

      assert %{"data" => next_names} = conn |> get(next) |> json_response(200)

      next_expirations =
        next_names
        |> Enum.map(fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)
        |> Enum.reverse()

      assert @default_limit = length(next_expirations)
      assert ^next_expirations = Enum.sort(next_expirations)
      assert Enum.at(expirations, @default_limit - 1) >= Enum.at(next_expirations, 0)
    end

    test "get active and inactive names, except those in auction, with limit=2", %{conn: conn} do
      limit = 2
      assert %{"data" => names} = conn |> get("/names", limit: limit) |> json_response(200)

      expirations =
        names
        |> Enum.map(fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)
        |> Enum.reverse()

      assert ^limit = length(names)
      assert ^expirations = Enum.sort(expirations)
    end

    test "get active and inactive names, except those in auction, with parameters by=name, direction=forward and limit=4",
         %{conn: conn} do
      limit = 4
      by = "name"
      direction = "forward"

      assert %{"data" => names} =
               conn
               |> get("/names", by: by, direction: direction, limit: limit)
               |> json_response(200)

      plain_names = Enum.map(names, fn %{"name" => plain_name} -> plain_name end)

      assert ^limit = length(names)
      assert ^plain_names = Enum.sort(plain_names)
    end

    test "renders error when parameter by is invalid", %{conn: conn} do
      by = "invalid_by"
      error_msg = "invalid query: by=#{by}"

      assert %{"error" => ^error_msg} = conn |> get("/names", by: by) |> json_response(400)
    end

    test "renders error when parameter direction is invalid", %{conn: conn} do
      by = "name"
      direction = "invalid_direction"
      error_msg = "invalid direction: #{direction}"

      %{"error" => ^error_msg} =
        conn |> get("/names", by: by, direction: direction) |> json_response(400)
    end

    test "it returns valid names on a given range", %{conn: conn} do
      first = 100_000
      last = 500_000

      assert %{"data" => data, "next" => next} =
               conn
               |> get("/names/gen/#{first}-#{last}")
               |> json_response(200)

      assert Enum.all?(data, fn %{"info" => %{"expire_height" => kbi}} ->
               first <= kbi and kbi <= last
             end)

      assert @default_limit = length(data)

      assert %{"data" => data2} =
               conn
               |> get(next)
               |> json_response(200)

      assert @default_limit = length(data2)

      assert Enum.all?(data2, fn %{"info" => %{"expire_height" => kbi}} ->
               first <= kbi and kbi <= last
             end)
    end

    test "it returns valid names on a given range, in reverse order", %{conn: conn} do
      first = 500_000
      last = 100_000

      assert %{"data" => data, "next" => next} =
               conn
               |> get("/names/gen/#{first}-#{last}")
               |> json_response(200)

      assert Enum.all?(data, fn %{"info" => %{"expire_height" => kbi}} ->
               last <= kbi and kbi <= first
             end)

      assert @default_limit = length(data)

      kbis =
        data |> Enum.map(fn %{"info" => %{"expire_height" => kbi}} -> kbi end) |> Enum.reverse()

      assert ^kbis = Enum.sort(kbis)
    end
  end

  describe "names" do
    test "it get active names backwards without any filters", %{conn: conn} do
      assert %{"data" => names, "next" => next} =
               conn |> get("/v2/names", state: "active") |> json_response(200)

      expirations =
        names
        |> Enum.map(fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)
        |> Enum.reverse()

      assert length(names) <= @default_limit
      assert ^expirations = Enum.sort(expirations)

      assert %{"data" => next_names, "prev" => prev_names} =
               conn |> get(next) |> json_response(200)

      if next do
        next_expirations =
          next_names
          |> Enum.map(fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)
          |> Enum.reverse()

        assert length(next_names) <= @default_limit
        assert ^next_expirations = Enum.sort(next_expirations)
        assert Enum.at(expirations, @default_limit - 1) >= Enum.at(next_expirations, 0)

        assert %{"data" => ^names} = conn |> get(prev_names) |> json_response(200)
      end
    end

    test "get active names forward with limit=4", %{conn: conn} do
      limit = 4

      assert %{"data" => names, "next" => next} =
               conn
               |> get("/v2/names", state: "active", direction: "forward", limit: limit)
               |> json_response(200)

      expirations =
        Enum.map(names, fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)

      assert length(names) <= limit
      assert ^expirations = Enum.sort(expirations)

      if next do
        assert %{"data" => next_names, "prev" => prev_names} =
                 conn |> get(next) |> json_response(200)

        next_expirations =
          Enum.map(next_names, fn %{"info" => %{"expire_height" => expire_height}} ->
            expire_height
          end)

        assert length(next_names) <= 4
        assert ^next_expirations = Enum.sort(next_expirations)
        assert Enum.at(expirations, limit - 1) <= Enum.at(next_expirations, 0)

        assert %{"data" => ^names} = conn |> get(prev_names) |> json_response(200)
      end
    end

    test "get active names with parameters by=name, direction=forward and limit=3", %{conn: conn} do
      by = "name"
      direction = "forward"
      limit = 3

      assert %{"data" => names} =
               conn
               |> get("/v2/names", state: "active", by: by, direction: direction, limit: limit)
               |> json_response(200)

      plain_names = Enum.map(names, fn %{"name" => name} -> name end)

      assert length(names) <= limit
      assert ^plain_names = Enum.sort(plain_names)
    end

    test "renders error when parameter by is invalid", %{conn: conn} do
      by = "invalid_by"
      error_msg = "invalid query: by=#{by}"

      assert %{"error" => ^error_msg} = conn |> get("/v2/names", by: by) |> json_response(400)
    end

    test "renders error when parameter direction is invalid", %{conn: conn} do
      by = "name"
      direction = "invalid_direction"
      error_msg = "invalid direction: #{direction}"

      assert %{"error" => ^error_msg} =
               conn |> get("/v2/names", by: by, direction: direction) |> json_response(400)
    end

    test "renders error when filtering by owner with expiration order", %{conn: conn} do
      id = "ak_KR3a8dukEYVoZPoWFaszFgjKUpBh7J1Q5iWsz9YCamHn2rTCp"
      error_msg = "invalid query: can't order by expiration when filtering by owner"

      assert %{"error" => ^error_msg} =
               conn |> get("/v2/names", owned_by: id) |> json_response(400)
    end

    test "renders error when scoping names sorted by name", %{conn: conn} do
      error_msg = "invalid query: can't scope names sorted by name"

      assert %{"error" => ^error_msg} =
               conn |> get("/v2/names", by: "name", scope: "gen:10-100") |> json_response(400)
    end

    test "it returns valid names on a given range", %{conn: conn} do
      first = 100_000
      last = 500_000

      assert %{"data" => data} =
               conn
               |> get("/v2/names", state: "active", scope: "gen:#{first}-#{last}")
               |> json_response(200)

      assert Enum.all?(data, fn %{"info" => %{"expire_height" => kbi}} ->
               first <= kbi and kbi <= last
             end)
    end

    test "it returns valid names on a given range, in reverse order", %{conn: conn} do
      first = 4_000_000
      last = 100_000

      assert %{"data" => data, "next" => next} =
               conn
               |> get("/v2/names", state: "active", scope: "gen:#{first}-#{last}")
               |> json_response(200)

      assert Enum.all?(data, fn %{"info" => %{"expire_height" => kbi}} ->
               last <= kbi and kbi <= first
             end)

      kbis =
        data |> Enum.map(fn %{"info" => %{"expire_height" => kbi}} -> kbi end) |> Enum.reverse()

      assert Enum.sort(kbis) == kbis
    end

    test "get inactive names with default limit", %{conn: conn} do
      assert %{"data" => names, "next" => next} =
               conn |> get("/v2/names", state: "inactive") |> json_response(200)

      expirations =
        names
        |> Enum.map(fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)
        |> Enum.reverse()

      assert @default_limit = length(names)
      assert ^expirations = Enum.sort(expirations)

      assert %{"data" => next_names, "prev" => prev_names} =
               conn |> get(next) |> json_response(200)

      next_expirations =
        next_names
        |> Enum.map(fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)
        |> Enum.reverse()

      assert @default_limit = length(next_names)
      assert ^next_expirations = Enum.sort(next_expirations)
      assert Enum.at(expirations, @default_limit - 1) >= Enum.at(next_expirations, 0)

      assert %{"data" => ^names} = conn |> get(prev_names) |> json_response(200)
    end

    test "get inactive names forward with limit=6", %{conn: conn} do
      limit = 4

      assert %{"data" => names, "next" => next} =
               conn
               |> get("/v2/names", state: "inactive", direction: "forward", limit: limit)
               |> json_response(200)

      expirations =
        Enum.map(names, fn %{"info" => %{"expire_height" => expire_height}} -> expire_height end)

      assert ^limit = length(names)
      assert ^expirations = Enum.sort(expirations)

      assert %{"data" => next_names, "prev" => prev_names} =
               conn |> get(next) |> json_response(200)

      next_expirations =
        Enum.map(next_names, fn %{"info" => %{"expire_height" => expire_height}} ->
          expire_height
        end)

      assert ^limit = length(next_names)
      assert ^next_expirations = Enum.sort(next_expirations)
      assert Enum.at(expirations, limit - 1) <= Enum.at(next_expirations, 0)

      assert %{"data" => ^names} = conn |> get(prev_names) |> json_response(200)
    end

    test "get inactive names with parameters by=name, direction=forward and limit=4", %{
      conn: conn
    } do
      by = "name"
      direction = "forward"
      limit = 4

      assert %{"data" => names} =
               conn
               |> get("/v2/names", state: "inactive", by: by, direction: direction, limit: limit)
               |> json_response(200)

      plain_names = Enum.map(names, fn %{"name" => name} -> name end)

      assert ^limit = length(names)
      assert ^plain_names = Enum.sort(plain_names)
    end

    test "it returns valid inactive names on a given range", %{conn: conn} do
      first = 100_000
      last = 500_000

      assert %{"data" => data, "next" => next} =
               conn
               |> get("/v2/names", state: "inactive", scope: "gen:#{first}-#{last}")
               |> json_response(200)

      assert Enum.all?(data, fn %{"info" => %{"expire_height" => kbi}} ->
               first <= kbi and kbi <= last
             end)

      assert @default_limit = length(data)

      assert %{"data" => data2} =
               conn
               |> get(next)
               |> json_response(200)

      assert @default_limit = length(data2)

      assert Enum.all?(data2, fn %{"info" => %{"expire_height" => kbi}} ->
               first <= kbi and kbi <= last
             end)
    end

    test "it returns valid inactive names on a given range, in reverse order", %{conn: conn} do
      first = 500_000
      last = 100_000

      assert %{"data" => data, "next" => next} =
               conn
               |> get("/v2/names", state: "inactive", scope: "gen:#{first}-#{last}")
               |> json_response(200)

      assert Enum.all?(data, fn %{"info" => %{"expire_height" => kbi}} ->
               last <= kbi and kbi <= first
             end)

      assert @default_limit = length(data)

      kbis =
        data |> Enum.map(fn %{"info" => %{"expire_height" => kbi}} -> kbi end) |> Enum.reverse()

      assert Enum.sort(kbis) == kbis
    end
  end

  describe "name_v1" do
    test "get info by plain name", %{conn: conn} do
      name = "wwwbeaconoidcom.chain"
      conn = get(conn, "/name/#{name}")

      assert json_response(conn, 200) ==
               TestUtil.handle_input(fn -> get_name(Validate.plain_name!(name)) end)
    end

    test "get by plain name a name with transfer by internal call", %{conn: conn} do
      name = "888888888888.chain"
      conn = get(conn, "/name/#{name}")

      assert json_response(conn, 200) ==
               TestUtil.handle_input(fn -> get_name(Validate.plain_name!(name)) end)
    end

    test "get name in auction with expand=true", %{conn: conn} do
      bid_key = Util.first(Model.AuctionBid)
      name = elem(bid_key, 0)
      conn = get(conn, "/name/#{name}?expand=true")

      response = json_response(conn, 200)
      name_map = TestUtil.handle_input(fn -> get_name(Validate.plain_name!(name)) end)
      name_map = update_in(name_map, ["status"], &to_string/1)

      assert name_map ==
               update_in(response, ["info", "bids"], fn bids ->
                 Enum.map(bids, & &1["tx_index"])
               end)

      assert List.first(response["info"]["bids"]) ==
               response["info"]["last_bid"] |> pop_in(["tx", "ttl"]) |> elem(1)
    end

    test "get name info by encoded hash ", %{conn: conn} do
      hash = "nm_MwcgT7ybkVYnKFV6bPqhwYq2mquekhZ2iDNTunJS2Rpz3Njuj"
      conn = get(conn, "/name/#{hash}")

      assert json_response(conn, 200) ==
               TestUtil.handle_input(fn -> get_name(Validate.plain_name!(hash)) end)
    end

    test "renders error when no such name is present", %{conn: conn} do
      name = "no--such--name--in--the--chain.chain"
      conn = get(conn, "/name/#{name}")

      assert json_response(conn, 404) == %{
               "error" => TestUtil.handle_input(fn -> get_name(Validate.plain_name!(name)) end)
             }
    end
  end

  describe "name" do
    test "get info by plain name", %{conn: conn} do
      name = "wwwbeaconoidcom.chain"
      conn = get(conn, "/v2/names/#{name}")

      assert json_response(conn, 200) ==
               TestUtil.handle_input(fn -> get_name(Validate.plain_name!(name)) end)
    end

    test "get by plain name a name with transfer by internal call", %{conn: conn} do
      name = "888888888888.chain"
      conn = get(conn, "/v2/names/#{name}")

      assert json_response(conn, 200) ==
               TestUtil.handle_input(fn -> get_name(Validate.plain_name!(name)) end)
    end

    test "get name in auction with expand=true", %{conn: conn} do
      bid_key = Util.first(Model.AuctionBid)
      name = elem(bid_key, 0)
      conn = get(conn, "/v2/names/#{name}?expand=true")

      response = json_response(conn, 200)
      name_map = TestUtil.handle_input(fn -> get_name(Validate.plain_name!(name)) end)
      name_map = update_in(name_map, ["status"], &to_string/1)

      assert name_map ==
               update_in(response, ["info", "bids"], fn bids ->
                 Enum.map(bids, & &1["tx_index"])
               end)

      assert List.first(response["info"]["bids"]) ==
               response["info"]["last_bid"] |> pop_in(["tx", "ttl"]) |> elem(1)
    end

    test "get name info by encoded hash ", %{conn: conn} do
      hash = "nm_MwcgT7ybkVYnKFV6bPqhwYq2mquekhZ2iDNTunJS2Rpz3Njuj"
      conn = get(conn, "/v2/names/#{hash}")

      assert json_response(conn, 200) ==
               TestUtil.handle_input(fn -> get_name(Validate.plain_name!(hash)) end)
    end

    test "renders error when no such name is present", %{conn: conn} do
      name = "no--such--name--in--the--chain.chain"
      conn = get(conn, "/v2/names/#{name}")

      assert json_response(conn, 404) == %{
               "error" => TestUtil.handle_input(fn -> get_name(Validate.plain_name!(name)) end)
             }
    end
  end

  describe "pointers_v1" do
    test "get pointers for valid given name", %{conn: conn} do
      id = "cryptodao21ae.chain"
      conn = get(conn, "/name/pointers/#{id}")

      assert json_response(conn, 200) ==
               TestUtil.handle_input(fn -> get_pointers(Validate.plain_name!(id)) end)
    end

    test "renders error when the name is missing", %{conn: conn} do
      id = "no--such--name--in--the--chain.chain"
      conn = get(conn, "/name/pointers/#{id}")

      assert json_response(conn, 404) == %{
               "error" => TestUtil.handle_input(fn -> get_pointers(Validate.plain_name!(id)) end)
             }
    end
  end

  describe "pointers" do
    test "get pointers for valid given name", %{conn: conn} do
      id = "cryptodao21ae.chain"
      conn = get(conn, "/v2/names/#{id}/pointers")

      assert json_response(conn, 200) ==
               TestUtil.handle_input(fn -> get_pointers(Validate.plain_name!(id)) end)
    end

    test "renders error when the name is missing", %{conn: conn} do
      id = "no--such--name--in--the--chain.chain"
      conn = get(conn, "/v2/names/#{id}/pointers")

      assert json_response(conn, 404) == %{
               "error" => TestUtil.handle_input(fn -> get_pointers(Validate.plain_name!(id)) end)
             }
    end
  end

  describe "pointees_v1" do
    test "get pointees for valid public key", %{conn: conn} do
      id = "ak_2HNsyfhFYgByVq8rzn7q4hRbijsa8LP1VN192zZwGm1JRYnB5C"
      conn = get(conn, "/name/pointees/#{id}")

      assert json_response(conn, 200) ==
               TestUtil.handle_input(fn -> get_pointees(Validate.name_id!(id)) end)
    end

    test "renders error when the key is invalid", %{conn: conn} do
      id = "ak_invalidkey"
      conn = get(conn, "/name/pointees/#{id}")

      assert json_response(conn, 400) ==
               %{
                 "error" =>
                   TestUtil.handle_input(fn ->
                     get_pointees(Validate.name_id!(id))
                   end)
               }
    end
  end

  describe "pointees" do
    test "get pointees for valid public key", %{conn: conn} do
      id = "ak_2HNsyfhFYgByVq8rzn7q4hRbijsa8LP1VN192zZwGm1JRYnB5C"
      conn = get(conn, "/v2/names/#{id}/pointees")

      assert json_response(conn, 200) ==
               TestUtil.handle_input(fn -> get_pointees(Validate.name_id!(id)) end)
    end

    test "renders error when the key is invalid", %{conn: conn} do
      id = "ak_invalidkey"
      conn = get(conn, "/v2/names/#{id}/pointees")

      assert json_response(conn, 400) ==
               %{
                 "error" =>
                   TestUtil.handle_input(fn ->
                     get_pointees(Validate.name_id!(id))
                   end)
               }
    end
  end

  describe "owned_by" do
    test "get active names owned by an account", %{conn: conn} do
      id = "ak_KR3a8dukEYVoZPoWFaszFgjKUpBh7J1Q5iWsz9YCamHn2rTCp"
      conn = get(conn, "/name/owned_by/#{id}")

      response = json_response(conn, 200)

      assert Enum.each(response["active"], fn %{
                                                "active" => true,
                                                "name" => plain_name,
                                                "hash" => hash,
                                                "info" => %{"ownership" => %{"current" => owner}}
                                              } ->
               assert owner == id

               expected_hash =
                 case :aens.get_name_hash(plain_name) do
                   {:ok, name_id_bin} -> Enc.encode(:name, name_id_bin)
                   _error -> nil
                 end

               assert hash == expected_hash
             end)
    end

    test "get inactive names that were owned by an account", %{conn: conn} do
      id = "ak_fCCw1JEkvXdztZxk8FRGNAkvmArhVeow89e64yX4AxbCPrVh5"
      conn = get(conn, Routes.name_path(conn, :owned_by, id, active: false))

      response = json_response(conn, 200)

      Enum.each(response["inactive"], fn %{
                                           "active" => false,
                                           "info" => %{"ownership" => %{"current" => last_owner}}
                                         } ->
        assert last_owner == id
      end)
    end

    test "renders error when the key is invalid", %{conn: conn} do
      id = "ak_invalid_key"
      conn = get(conn, "/name/owned_by/#{id}")

      assert json_response(conn, 400) == %{"error" => "invalid id: #{id}"}
    end
  end

  describe "search_v1" do
    test "it returns an all matching names & auctions forward", %{conn: conn} do
      prefix = "xyz"

      names_and_auctions = conn |> get("/names/search/#{prefix}") |> json_response(200)
      plain_names = Enum.map(names_and_auctions, fn %{"name" => name} -> name end)

      assert ^plain_names = Enum.sort(plain_names)
      assert Enum.all?(plain_names, &String.starts_with?(&1, prefix))
    end
  end

  describe "search" do
    test "it returns an all matching names & auctions", %{conn: conn} do
      prefix = "xyz"

      assert %{"data" => names_and_auctions, "next" => next} =
               conn |> get("/v2/names/search", prefix: prefix) |> json_response(200)

      plain_names =
        names_and_auctions
        |> Enum.map(fn
          %{"type" => "name", "payload" => %{"name" => name}} -> name
          %{"type" => "auction", "payload" => %{"name" => name}} -> name
        end)
        |> Enum.reverse()

      assert @default_limit = length(names_and_auctions)
      assert ^plain_names = Enum.sort(plain_names)
      assert Enum.all?(plain_names, &String.starts_with?(&1, prefix))

      %{"data" => next_names_and_auctions} = conn |> get(next) |> json_response(200)

      next_plain_names =
        next_names_and_auctions
        |> Enum.map(fn
          %{"type" => "name", "payload" => %{"name" => name}} -> name
          %{"type" => "auction", "payload" => %{"name" => name}} -> name
        end)
        |> Enum.reverse()

      assert @default_limit = length(next_names_and_auctions)
      assert ^next_plain_names = Enum.sort(next_plain_names)
      assert Enum.all?(next_plain_names, &String.starts_with?(&1, prefix))

      assert Enum.at(plain_names, @default_limit - 1) >= Enum.at(next_plain_names, 0)
    end

    test "it returns an all matching names & auctions forward", %{conn: conn} do
      prefix = "xyz"

      assert %{"data" => names_and_auctions, "next" => next} =
               conn
               |> get("/v2/names/search", prefix: prefix, direction: "forward")
               |> json_response(200)

      plain_names =
        Enum.map(names_and_auctions, fn
          %{"type" => "name", "payload" => %{"name" => name}} -> name
          %{"type" => "auction", "payload" => %{"name" => name}} -> name
        end)

      assert @default_limit = length(names_and_auctions)
      assert ^plain_names = Enum.sort(plain_names)
      assert Enum.all?(plain_names, &String.starts_with?(&1, prefix))

      %{"data" => next_names_and_auctions} = conn |> get(next) |> json_response(200)

      next_plain_names =
        Enum.map(next_names_and_auctions, fn
          %{"type" => "name", "payload" => %{"name" => name}} -> name
          %{"type" => "auction", "payload" => %{"name" => name}} -> name
        end)

      assert @default_limit = length(next_names_and_auctions)
      assert ^next_plain_names = Enum.sort(next_plain_names)
      assert Enum.all?(next_plain_names, &String.starts_with?(&1, prefix))

      assert Enum.at(plain_names, @default_limit - 1) >= Enum.at(next_plain_names, 0)
    end
  end

  ##########

  defp get_name(name) do
    case Name.locate(name) do
      {info, source} ->
        Format.to_map(info, source)

      nil ->
        raise ErrInput.NotFound, value: name
    end
  end

  defp get_pointers(name) do
    case Name.locate(name) do
      {m_name, Model.ActiveName} ->
        Format.map_raw_values(Name.pointers(m_name), &Format.to_json/1)

      {_info, Model.InactiveName} ->
        raise ErrInput.Expired, value: name

      _not_found ->
        raise ErrInput.NotFound, value: name
    end
  end

  defp get_pointees(pubkey) do
    {active, inactive} = Name.pointees(pubkey)

    %{
      "active" => Format.map_raw_values(active, &Format.to_json/1),
      "inactive" => Format.map_raw_values(inactive, &Format.to_json/1)
    }
  end
end
