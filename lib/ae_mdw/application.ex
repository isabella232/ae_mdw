defmodule AeMdw.Application do
  alias AeMdw.Db.Model
  alias AeMdw.EtsCache
  alias AeMdw.Extract
  alias AeMdw.Contract

  require Model

  use Application

  import AeMdw.Util

  ##########

  def start(_type, _args) do
    :lager.set_loglevel(:epoch_sync_lager_event, :lager_console_backend, :undefined, :error)
    :lager.set_loglevel(:lager_console_backend, :error)

    init(:model_records)
    init(:node_records)
    init(:meta)
    init(:contract_cache)
    init(:aehttp)
    init(:db_state)
    # init(:aesophia)

    children =
      [AeMdw.RocksdbManager,
       AeMdw.Sync.Watcher,
       AeMdw.Sync.Supervisor,
       AeMdwWeb.Supervisor,
       AeMdwWeb.Websocket.Supervisor]

    {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
    Application.fetch_env!(:ae_mdw, :sync) && sync(true)
    {:ok, sup_pid}
  end

  def sync(enabled?) when is_boolean(enabled?),
    do: AeMdw.Sync.Supervisor.sync(enabled?)

  def init(:aehttp),
    do: :application.ensure_all_started(:aehttp)

  # def init(:aesophia) do
  #   Path.join(Application.app_dir(:aesophia), "ebin/*.beam")
  #   |> Path.wildcard
  #   |> Enum.map(&:code.load_abs(to_charlist(Path.rootname(&1))))
  # end

  def init(:model_records),
    do: Enum.each(Model.records(), &SmartRecord.new(Model, &1, Model.defaults(&1)))

  def init(:node_records) do
    {:ok, aeo_oracles_code} = Extract.AbsCode.module(:aeo_oracles)
    {:ok, aeo_query_code} = Extract.AbsCode.module(:aeo_query)

    oracle_fields = record_keys(aeo_oracles_code, :oracle)
    query_fields = record_keys(aeo_query_code, :query)

    SmartRecord.new(AeMdw.Node, :oracle, Enum.zip(oracle_fields, Stream.cycle([nil])))
    SmartRecord.new(AeMdw.Node, :oracle_query, Enum.zip(query_fields, Stream.cycle([nil])))
    :ok
  end

  def init(:meta) do
    {:ok, chain_state_code} = Extract.AbsCode.module(:aec_chain_state)
    [:header, :hash, :type] = record_keys(chain_state_code, :node)

    {:ok, aetx_code} = Extract.AbsCode.module(:aetx)
    {:ok, aeser_code} = Extract.AbsCode.module(:aeser_api_encoder)
    {:ok, headers_code} = Extract.AbsCode.module(:aec_headers)
    {:ok, aens_state_tree_code} = Extract.AbsCode.module(:aens_state_tree)
    {:ok, aeo_state_tree_code} = Extract.AbsCode.module(:aeo_state_tree)

    network_id = :aec_governance.get_network_id()

    hard_fork_heights =
      network_id
      |> :aec_hard_forks.protocols_from_network_id()
      |> Enum.sort_by(&elem(&1, 0))

    lima_vsn = :aec_hard_forks.protocol_vsn(:lima)

    lima_height =
      Enum.find_value(hard_fork_heights, fn
        {^lima_vsn, h} -> h
        _ -> nil
      end)

    type_mod_map = Extract.tx_mod_map(aetx_code)
    type_name_map = Extract.tx_name_map(aetx_code)
    id_prefix_type_map = Extract.id_prefix_type_map(aeser_code)
    id_type_map = Extract.id_type_map(aeser_code)
    type_mod_mapper = &Map.fetch!(type_mod_map, &1)

    {tx_field_types, tx_fields, tx_ids} =
      Enum.reduce(type_mod_map, {%{}, %{}, %{}}, fn {type, _},
                                                    {tx_field_types, tx_fields, tx_ids} ->
        {fields, ids} = Extract.tx_record_info(type, type_mod_mapper)

        tx_field_types =
          for {id_field, _} <- ids, reduce: tx_field_types do
            acc ->
              update_in(acc, [id_field], fn set -> MapSet.put(set || MapSet.new(), type) end)
          end

        {tx_field_types, put_in(tx_fields[type], fields), put_in(tx_ids[type], ids)}
      end)

    id_field_type_map =
      Enum.reduce(tx_ids, %{}, fn {type, ids_map}, acc ->
        for {field, pos} <- ids_map,
            reduce: acc,
            do: (acc -> Map.put(acc, [field], Map.put(Map.get(acc, [field], %{}), type, pos)))
      end)

    id_fields = Map.keys(id_field_type_map) |> Enum.map(compose(&to_string/1, &hd/1))

    stream_mod = fn db_mod ->
      ["AeMdw", "Db", "Model", tab] = Module.split(db_mod)
      Module.concat(AeMdw.Db.Stream, tab)
    end

    collect_stream_mod = fn t, acc -> put_in(acc[t], stream_mod.(t)) end

    tx_types = Map.keys(type_mod_map)
    tx_group = &("#{&1}" |> String.split("_") |> hd |> String.to_atom())
    tx_group_map = Enum.group_by(tx_types, tx_group)

    tx_prefix = fn tx_type ->
      str = to_string(tx_type)
      # drop "_tx"
      String.slice(str, 0, String.length(str) - 3)
    end

    field_pos_map = fn code, rec ->
      record_keys(code, rec)
      |> Stream.zip(Stream.iterate(1, &(&1 + 1)))
      |> Enum.into(%{})
    end

    aex9_sigs =
      AeMdw.Contract.aex9_signatures()
      |> Enum.map(fn {k, v} -> {Contract.function_hash(k), v} end)
      |> Enum.into(%{})

    max_int = AeMdw.Util.max_256bit_int()
    max_blob = :binary.list_to_bin(:lists.duplicate(1024, <<max_int::256>>))

    height_proto = :aec_hard_forks.protocols() |> Enum.into([]) |> Enum.sort(&>=/2)

    min_block_reward_height =
      :aec_block_genesis.height() + :aec_governance.beneficiary_reward_delay() + 1

    SmartGlobal.new(
      AeMdw.Node,
      %{
        tx_mod: type_mod_map,
        tx_name: type_name_map,
        tx_type: AeMdw.Util.inverse(type_name_map),
        tx_fields: tx_fields,
        tx_ids: tx_ids,
        id_prefix: id_prefix_type_map,
        id_field_type: id_field_type_map |> Enum.concat([{[:_], nil}]),
        id_fields: [{[], MapSet.new(id_fields)}],
        tx_field_types: tx_field_types,
        tx_types: [{[], MapSet.new(tx_types)}],
        tx_prefixes: [{[], MapSet.new(tx_types |> Enum.map(tx_prefix))}],
        id_prefixes: [{[], MapSet.new(Map.keys(id_prefix_type_map))}],
        stream_mod: Enum.reduce(Model.tables(), %{}, collect_stream_mod),
        tx_group: tx_group_map,
        tx_groups: [{[], MapSet.new(Map.keys(tx_group_map))}],
        id_type: id_type_map,
        type_id: AeMdw.Util.inverse(id_type_map),
        hdr_fields: %{
          key: record_keys(headers_code, :key_header),
          micro: record_keys(headers_code, :mic_header)
        },
        aens_tree_pos: field_pos_map.(aens_state_tree_code, :ns_tree),
        aeo_tree_pos: field_pos_map.(aeo_state_tree_code, :oracle_tree),
        lima_vsn: [{[], lima_vsn}],
        lima_height: [{[], lima_height}],
        aex9_signatures: [{[], aex9_sigs}],
        aex9_transfer_event_hash: [{[], :aec_hash.blake2b_256_hash("Transfer")}],
        max_blob: [{[], max_blob}],
        height_proto: [{[], height_proto}],
        min_block_reward_height: [{[], min_block_reward_height}],
        token_supply_delta:
          Enum.map(token_supply_delta(), fn {h, xs} -> {[h], xs} end) ++ [{[:_], 0}]
      }
    )
  end

  def init(:contract_cache) do
    cache_exp = Application.fetch_env!(:ae_mdw, :contract_cache_expiration_minutes)
    EtsCache.new(AeMdw.Contract.table(), cache_exp)
  end

  def init(:db_state) do
    initial_token_supply = AeMdw.Node.token_supply_delta(0)

    :mnesia.transaction(fn ->
      case :mnesia.read(Model.SumStat, 0) do
        [m_stat] ->
          tot_sup = Model.sum_stat(m_stat, :total_supply)
          tot_sup == initial_token_supply || raise "initial total supply doesn't match"

        [] ->
          m_stat = Model.sum_stat(index: 0, total_supply: initial_token_supply)
          :mnesia.write(Model.SumStat, m_stat, :write)
      end
    end)
  end

  def record_keys(mod_code, rec_name) do
    {:ok, rec_code} = Extract.AbsCode.record_fields(mod_code, rec_name)
    Enum.map(rec_code, &elem(Extract.AbsCode.field_name_type(&1), 0))
  end

  def mints() do
    node_dir = Application.fetch_env!(:ae_plugin, :node_root)
    # Note: Path.wildcard ignores symlinks...
    acc_files = [_ | _] = :filelib.wildcard('#{node_dir}/**/accounts.json')

    acc_files
    |> Enum.map(fn f ->
      f = to_string(f)

      hf =
        Path.dirname(f)
        |> Path.split()
        |> Enum.at(-1)
        |> String.trim_leading(".")

      {hf, Jason.decode!(File.read!(f))}
    end)
    |> Enum.into(%{})
  end

  def token_supply_delta() do
    sum_vals = compose(&Enum.sum/1, &Map.values/1)
    {genesis_accs, hfs} = Map.pop(mints(), "genesis")

    [
      {0, sum_vals.(genesis_accs)}
      | hfs
        |> Enum.map(fn {hf, accs} ->
          proto = String.to_existing_atom(hf)
          proto_vsn = :aec_hard_forks.protocol_vsn(proto)
          height = :aec_hard_forks.protocols()[proto_vsn]
          {height, sum_vals.(accs)}
        end)
        |> Enum.sort()
    ]
  end

  # Tell Phoenix to update the endpoint configuration whenever the application is updated.
  def config_change(changed, _new, removed) do
    AeMdwWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
