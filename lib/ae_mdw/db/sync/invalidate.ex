defmodule AeMdw.Db.Sync.Invalidate do
  alias AeMdw.Node, as: AE
  alias AeMdw.Db.Stream, as: DBS
  alias AeMdw.Db.{Model, Sync, Format}
  alias AeMdw.Log

  require Model

  import AeMdw.{Util, Db.Util}

  ##########

  def invalidate(fork_height) when is_integer(fork_height) do
    prev_kbi = fork_height - 1
    from_txi = Model.block(read_block!({prev_kbi, -1}), :tx_index)

    cond do
      is_integer(from_txi) && from_txi >= 0 ->
        Log.info("invalidating from tx #{from_txi} at generation #{prev_kbi}")
        bi_keys = block_keys_range({fork_height - 1, 0})
        {tx_keys, id_counts} = tx_keys_range(from_txi)
        {aex9_keys, aex9_sym_keys, aex9_rev_keys} = aex9_keys_range(from_txi)
        tab_keys = Map.merge(bi_keys, tx_keys)

        :mnesia.transaction(fn ->
          {name_dels, name_writes} = Sync.Name.invalidate(fork_height - 1)
          {oracle_dels, oracle_writes} = Sync.Oracle.invalidate(fork_height - 1)

          do_dels(tab_keys)
          do_dels(name_dels, &AeMdw.Db.Name.cache_through_delete/2)
          do_dels(oracle_dels, &AeMdw.Db.Oracle.cache_through_delete/2)

          do_dels(%{Model.Aex9Contract => aex9_keys,
                    Model.Aex9ContractSymbol => aex9_sym_keys,
                    Model.RevAex9Contract => aex9_rev_keys})

          do_writes(name_writes, &AeMdw.Db.Name.cache_through_write/2)
          do_writes(oracle_writes, &AeMdw.Db.Oracle.cache_through_write/2)

          Enum.each(id_counts, fn {f_key, delta} -> Model.update_count(f_key, -delta) end)
        end)

      # wasn't synced up to that txi, nothing to do
      true ->
        :ok
    end
  end

  ################################################################################
  # Invalidations - keys for records to delete in case of fork

  def block_keys_range({_, _} = from_bi),
    do: %{
      Model.Block =>
        collect_keys(Model.Block, [from_bi], from_bi, &:mnesia.next/2, &{:cont, [&1 | &2]})
    }

  def tx_keys_range(from_txi),
    do: tx_keys_range(from_txi, last(Model.Tx))

  def tx_keys_range(from_txi, to_txi) when from_txi > to_txi,
    do: %{}

  def tx_keys_range(from_txi, to_txi) when from_txi <= to_txi do
    tx_keys = Enum.to_list(from_txi..to_txi)

    {type_keys, field_keys, field_counts} = type_fields_keys(tx_keys)

    time_keys = time_keys_range(from_txi, to_txi)
    {origin_keys, rev_origin_keys} = origin_keys_range(from_txi, to_txi)

    {%{
       Model.Tx => tx_keys,
       Model.Type => type_keys,
       Model.Time => time_keys,
       Model.Field => field_keys,
       Model.Origin => origin_keys,
       Model.RevOrigin => rev_origin_keys
     }, %{Model.IdCount => field_counts}}
  end

  def type_fields_keys(txis) do
    Enum.reduce(txis, {[], [], %{}}, fn txi, {type_keys, field_keys, field_counts} ->
      %{tx: %{type: tx_type} = tx, hash: tx_hash} = Format.to_raw_map(read_tx!(txi))

      {fields, f_counts} =
        for {id_key, pos} <- AE.tx_ids(tx_type), reduce: {[], field_counts} do
          {fxs, fcs} ->
            pk = pk(tx[id_key])
            {[{tx_type, pos, pk, txi} | fxs], Map.update(fcs, {tx_type, pos, pk}, 1, &(&1 + 1))}
        end

      {fields, f_counts} =
        case link_del_keys(tx_type, tx_hash, txi) do
          {link_key_txi, link_key_count} ->
            {[link_key_txi | fields], Map.update(f_counts, link_key_count, 1, &(&1 + 1))}

          nil ->
            {fields, f_counts}
        end

      {[{tx_type, txi} | type_keys], fields ++ field_keys, f_counts}
    end)
  end

  def link_del_keys(tx_type, tx_hash, txi) do
    with pk = <<_::binary>> <- link_del_pubkey(tx_type, tx_hash) do
      link_key = {tx_type, nil, pk, txi}
      incr_key = {tx_type, nil, pk}
      {link_key, incr_key}
    end
  end

  def link_del_pubkey(:contract_create_tx, tx_hash),
    do: :aect_contracts.pubkey(:aect_contracts.new(AE.Db.get_tx(tx_hash)))

  def link_del_pubkey(:channel_create_tx, tx_hash),
    do: ok!(:aesc_utils.channel_pubkey(AE.Db.get_signed_tx(tx_hash)))

  def link_del_pubkey(:oracle_register_tx, tx_hash),
    do: :aeo_register_tx.account_pubkey(AE.Db.get_tx(tx_hash))

  def link_del_pubkey(:name_claim_tx, tx_hash),
    do: ok!(:aens.get_name_hash(:aens_claim_tx.name(AE.Db.get_tx(tx_hash))))

  def link_del_pubkey(_type, _tx_hash),
    do: nil

  def time_keys_range(from_txi, to_txi) do
    bi_time = fn bi ->
      Model.block(read!(Model.Block, bi), :hash)
      |> :aec_db.get_header()
      |> :aec_headers.time_in_msecs()
    end

    from_bi = Model.tx(read_tx!(from_txi), :block_index)

    folder = fn tx, {bi, time, acc} ->
      case Model.tx(tx, :block_index) do
        ^bi ->
          {bi, time, [{time, Model.tx(tx, :index)} | acc]}

        new_bi ->
          new_time = bi_time.(new_bi)
          {new_bi, new_time, [{new_time, Model.tx(tx, :index)} | acc]}
      end
    end

    {_, _, keys} =
      DBS.map(from_txi..to_txi, & &1)
      |> Enum.reduce({from_bi, bi_time.(from_bi), []}, folder)

    keys
  end

  def origin_keys_range(from_txi, to_txi) do
    case :mnesia.dirty_next(Model.RevOrigin, {from_txi, :_, nil}) do
      :"$end_of_table" ->
        {[], []}

      start_key ->
        push_key = fn {txi, pk_type, pk}, {origins, rev_origins} ->
          {[{pk_type, pk, txi} | origins], [{txi, pk_type, pk} | rev_origins]}
        end

        collect_keys(Model.RevOrigin, push_key.(start_key, {[], []}), start_key, &next/2, fn
          {txi, pk_type, pk}, acc when txi <= to_txi ->
            {:cont, push_key.({txi, pk_type, pk}, acc)}

          {txi, _, _}, acc when txi > to_txi ->
            {:halt, acc}
        end)
    end
  end

  def aex9_keys_range(from_txi) do
    case :mnesia.dirty_next(Model.RevAex9Contract, {from_txi, nil, nil, nil}) do
      :"$end_of_table" ->
        {[], []}

      start_key ->
        push_key = fn {txi, name, symbol, decimals}, {contracts, symbols, rev_contracts} ->
          {[{name, symbol, txi, decimals} | contracts],
           [{symbol, name, txi, decimals} | symbols],
           [{txi, name, symbol, decimals} | rev_contracts]}
        end

        collect_keys(Model.RevAex9Contract,
          push_key.(start_key, {[], [], []}), start_key, &next/2,
          fn key, acc -> {:cont, push_key.(key, acc)} end)
    end
  end

  ##########

  defp pk({:id, _, _} = id) do
    {_, pk} = :aeser_id.specialize(id)
    pk
  end

  # defp log_del_keys(tab_keys) do
  #   {blocks, tab_keys} = Map.pop(tab_keys, ~t[block])
  #   {txs, tab_keys} = Map.pop(tab_keys, ~t[tx])
  #   [b_count, t_count] = [blocks, txs] |> Enum.map(&Enum.count/1)
  #   {b1, b2} = {List.last(blocks), List.first(blocks)}
  #   {t1, t2} = {List.first(txs), List.last(txs)}
  #   Log.info("table block has #{b_count} records to delete: #{inspect(b1)}..#{inspect(b2)}")
  #   Log.info("table tx has #{t_count} records to delete: #{t1}..#{t2}")
  #   for {tab, keys} <- tab_keys,
  #       do: Log.info("table #{Model.record(tab)} has #{Enum.count(keys)} records to delete")
  #   :ok
  # end
end
