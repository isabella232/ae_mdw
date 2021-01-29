defmodule AeMdw.Db.Model do
  require Record
  require Ex2ms

  import Record, only: [defrecord: 2]

  ################################################################################

  # txs block index :
  #     index = {kb_index (0..), mb_index}, tx_index = tx_index, hash = block (header) hash
  #     if tx_index == nil -> txs not synced yet on that height
  #     if tx_index == -1  -> no tx occured yet
  #     On keyblock boundary: mb_index = -1}
  @block_defaults [index: {-1, -1}, tx_index: nil, hash: <<>>]
  defrecord :block, @block_defaults

  # txs table :
  #     index = tx_index (0..), id = tx_id
  @tx_defaults [index: -1, id: <<>>, block_index: {-1, -1}, time: -1]
  defrecord :tx, @tx_defaults

  # txs time index :
  #     index = {mb_time_msecs (0..), tx_index = (0...)},
  @time_defaults [index: {-1, -1}, unused: nil]
  defrecord :time, @time_defaults

  # txs type index  :
  #     index = {tx_type, tx_index}
  @type_defaults [index: {nil, -1}, unused: nil]
  defrecord :type, @type_defaults

  # txs fields      :
  #     index = {tx_type, tx_field_pos, object_pubkey, tx_index},
  @field_defaults [index: {nil, -1, nil, -1}, unused: nil]
  defrecord :field, @field_defaults

  # id counts       :
  #     index = {tx_type, tx_field_pos, object_pubkey}
  @id_count_defaults [index: {nil, nil, nil}, count: 0]
  defrecord :id_count, @id_count_defaults

  # object origin :
  #     index = {tx_type, pubkey, tx_index}, tx_id = tx_hash
  @origin_defaults [index: {nil, nil, nil}, tx_id: nil]
  defrecord :origin, @origin_defaults

  # we need this one to quickly locate origin keys to delete for invalidating a fork
  #
  # rev object origin :
  #     index = {tx_index, tx_type, pubkey}
  @rev_origin_defaults [index: {nil, nil, nil}, unused: nil]
  defrecord :rev_origin, @rev_origin_defaults

  # plain name:
  #     index = name_hash, plain = plain name
  @plain_name_defaults [index: nil, value: nil]
  defrecord :plain_name, @plain_name_defaults

  # auction bid:
  #     index = {plain_name, {block_index, txi}, expire_height = height, owner = pk, prev_bids = []}
  @auction_bid_defaults [index: {nil, {{nil, nil}, nil}, nil, nil, nil}, unused: nil]
  defrecord :auction_bid, @auction_bid_defaults

  # in 3 tables: auction_expiration, name_expiration, inactive_name_expiration
  #
  # expiration:
  #     index = {expire_height, plain_name | oracle_pk}, value: any
  @expiration_defaults [index: {nil, nil}, value: nil]
  defrecord :expiration, @expiration_defaults

  # in 2 tables: active_name, inactive_name
  #
  # name:
  #     index = plain_name,
  #     active = height                    #
  #     expire = height                    #
  #     claims =  [{block_index, txi}]     #
  #     updates = [{block_index, txi}]     #
  #     transfers = [{block_index, txi}]   #
  #     revoke = {block_index, txi} | nil  #
  #     auction_timeout = int              # 0 if not auctioned
  #     owner = pubkey                     #
  #     previous = m_name | nil            # previus epoch of the same name
  #
  #     (other info (pointers, owner) is from looking up last update tx)
  @name_defaults [
    index: nil,
    active: nil,
    expire: nil,
    claims: [],
    updates: [],
    transfers: [],
    revoke: nil,
    auction_timeout: 0,
    owner: nil,
    previous: nil
  ]
  defrecord :name, @name_defaults

  # owner: (updated via name claim/transfer)
  #     index = {pubkey, entity},
  @owner_defaults [index: nil, unused: nil]
  defrecord :owner, @owner_defaults

  # pointee : (updated when name_update_tx changes pointers)
  #     index = {pointer_val, {block_index, txi}, pointer_key}
  @pointee_defaults [index: {nil, {{nil, nil}, nil}, nil}, unused: nil]
  defrecord :pointee, @pointee_defaults

  # in 2 tables: active_oracle, inactive_oracle
  #
  # oracle:
  #     index: pubkey
  #     active: height
  #     expire: height
  #     register: {block_index, txi}
  #     extends: [{block_index, txi}]
  #     previous: m_oracle | nil
  #
  #     (other details come from MPT lookup)
  @oracle_defaults [
    index: nil,
    active: nil,
    expire: nil,
    register: nil,
    extends: [],
    previous: nil
  ]
  defrecord :oracle, @oracle_defaults

  # AEX9 contract:
  #     index: {name, symbol, txi, decimals}
  @aex9_contract_defaults [
    index: {nil, nil, nil, nil},
    unused: nil
  ]
  defrecord :aex9_contract, @aex9_contract_defaults

  # AEX9 contract symbol:
  #     index: {symbol, name, txi, decimals}
  @aex9_contract_symbol_defaults [
    index: {nil, nil, nil, nil},
    unused: nil
  ]
  defrecord :aex9_contract_symbol, @aex9_contract_symbol_defaults

  # rev AEX9 contract:
  #     index: {txi, name, symbol, decimals}
  @rev_aex9_contract_defaults [
    index: {nil, nil, nil, nil},
    unused: nil
  ]
  defrecord :rev_aex9_contract, @rev_aex9_contract_defaults

  # AEX9 contract pubkey:
  #     index: pubkey
  #     txi: txi
  @aex9_contract_pubkey_defaults [
    index: nil,
    txi: nil
  ]
  defrecord :aex9_contract_pubkey, @aex9_contract_pubkey_defaults

  # contract call:
  #     index: {create txi, call txi}
  #     fun: ""
  #     args: []
  #     result: :ok
  #     return: nil
  @contract_call_defaults [
    index: {-1, -1},
    fun: nil,
    args: nil,
    result: nil,
    return: nil
  ]
  defrecord :contract_call, @contract_call_defaults

  # contract log:
  #     index: {create txi, call txi, event hash, log idx}
  #     ext_contract: nil || ext_contract_pk
  #     args: []
  #     data: ""
  @contract_log_defaults [
    index: {-1, -1, nil, -1},
    ext_contract: nil,
    args: [],
    data: ""
  ]
  defrecord :contract_log, @contract_log_defaults

  # data contract log:
  #     index: {data, call txi, create txi, event hash, log idx}
  @data_contract_log_defaults [
    index: {nil, -1, -1, nil, -1},
    unused: nil
  ]
  defrecord :data_contract_log, @data_contract_log_defaults

  # evt contract log:
  #     index: {event hash, call txi, create txi, log idx}
  @evt_contract_log_defaults [
    index: {nil, -1, -1, -1},
    unused: nil
  ]
  defrecord :evt_contract_log, @evt_contract_log_defaults

  # idx contract log:
  #     index: {call txi, create txi, event hash, log idx}
  @idx_contract_log_defaults [
    index: {-1, -1, nil, -1},
    unused: nil
  ]
  defrecord :idx_contract_log, @idx_contract_log_defaults

  # aex9 transfer:
  #    index: {from pk, to pk, amount, call txi, log idx}
  @aex9_transfer_defaults [
    index: {nil, nil, -1, -1, -1},
    unused: nil
  ]
  defrecord :aex9_transfer, @aex9_transfer_defaults

  # rev aex9 transfer:
  #    index: {to pk, from pk, amount, call txi, log idx}
  @rev_aex9_transfer_defaults [
    index: {nil, nil, -1, -1, -1},
    unused: nil
  ]
  defrecord :rev_aex9_transfer, @rev_aex9_transfer_defaults

  # idx aex9 transfer:
  #    index: {call txi, log idx, from pk, to pk, amount}
  @idx_aex9_transfer_defaults [
    index: {-1, -1, nil, nil, -1},
    unused: nil
  ]
  defrecord :idx_aex9_transfer, @idx_aex9_transfer_defaults

  # aex9 account presence:
  #    index: {account pk, create or call txi, contract pk}
  @aex9_account_presence_defaults [
    index: {nil, -1, nil},
    unused: nil
  ]
  defrecord :aex9_account_presence, @aex9_account_presence_defaults

  # idx_aex9_account_presence:
  #    index: {create or call txi, account pk, contract pk}
  @idx_aex9_account_presence_defaults [
    index: {-1, nil, nil},
    unused: nil
  ]
  defrecord :idx_aex9_account_presence, @idx_aex9_account_presence_defaults

  ################################################################################

  def tables(),
    do: Enum.concat([chain_tables(), name_tables(), contract_tables(), oracle_tables()])

  def chain_tables() do
    [
      AeMdw.Db.Model.Tx,
      AeMdw.Db.Model.Block,
      AeMdw.Db.Model.Time,
      AeMdw.Db.Model.Type,
      AeMdw.Db.Model.Field,
      AeMdw.Db.Model.IdCount,
      AeMdw.Db.Model.Origin,
      AeMdw.Db.Model.RevOrigin
    ]
  end

  def contract_tables() do
    [
      AeMdw.Db.Model.Aex9Contract,
      AeMdw.Db.Model.Aex9ContractSymbol,
      AeMdw.Db.Model.RevAex9Contract,
      AeMdw.Db.Model.Aex9ContractPubkey,
      AeMdw.Db.Model.Aex9Transfer,
      AeMdw.Db.Model.RevAex9Transfer,
      AeMdw.Db.Model.IdxAex9Transfer,
      AeMdw.Db.Model.Aex9AccountPresence,
      AeMdw.Db.Model.IdxAex9AccountPresence,
      AeMdw.Db.Model.ContractCall,
      AeMdw.Db.Model.ContractLog,
      AeMdw.Db.Model.DataContractLog,
      AeMdw.Db.Model.EvtContractLog,
      AeMdw.Db.Model.IdxContractLog
    ]
  end

  def name_tables() do
    [
      AeMdw.Db.Model.PlainName,
      AeMdw.Db.Model.AuctionBid,
      AeMdw.Db.Model.Pointee,
      AeMdw.Db.Model.AuctionExpiration,
      AeMdw.Db.Model.ActiveNameExpiration,
      AeMdw.Db.Model.InactiveNameExpiration,
      AeMdw.Db.Model.ActiveName,
      AeMdw.Db.Model.InactiveName,
      AeMdw.Db.Model.AuctionOwner,
      AeMdw.Db.Model.ActiveNameOwner
    ]
  end

  def oracle_tables() do
    [
      AeMdw.Db.Model.ActiveOracleExpiration,
      AeMdw.Db.Model.InactiveOracleExpiration,
      AeMdw.Db.Model.ActiveOracle,
      AeMdw.Db.Model.InactiveOracle
    ]
  end

  def records(),
    do: [
      :tx,
      :block,
      :time,
      :type,
      :field,
      :id_count,
      :origin,
      :rev_origin,
      :aex9_contract,
      :aex9_contract_symbol,
      :rev_aex9_contract,
      :aex9_contract_pubkey,
      :aex9_transfer,
      :rev_aex9_transfer,
      :idx_aex9_transfer,
      :aex9_account_presence,
      :idx_aex9_account_presence,
      :contract_call,
      :contract_log,
      :data_contract_log,
      :evt_contract_log,
      :idx_contract_log,
      :plain_name,
      :auction_bid,
      :expiration,
      :name,
      :owner,
      :pointee,
      :oracle
    ]

  def fields(record),
    do: for({x, _} <- defaults(record), do: x)

  def record(AeMdw.Db.Model.Tx), do: :tx
  def record(AeMdw.Db.Model.Block), do: :block
  def record(AeMdw.Db.Model.Time), do: :time
  def record(AeMdw.Db.Model.Type), do: :type
  def record(AeMdw.Db.Model.Field), do: :field
  def record(AeMdw.Db.Model.IdCount), do: :id_count
  def record(AeMdw.Db.Model.Origin), do: :origin
  def record(AeMdw.Db.Model.RevOrigin), do: :rev_origin
  def record(AeMdw.Db.Model.Aex9Contract), do: :aex9_contract
  def record(AeMdw.Db.Model.Aex9ContractSymbol), do: :aex9_contract_symbol
  def record(AeMdw.Db.Model.RevAex9Contract), do: :rev_aex9_contract
  def record(AeMdw.Db.Model.Aex9ContractPubkey), do: :aex9_contract_pubkey
  def record(AeMdw.Db.Model.Aex9Transfer), do: :aex9_transfer
  def record(AeMdw.Db.Model.RevAex9Transfer), do: :rev_aex9_transfer
  def record(AeMdw.Db.Model.IdxAex9Transfer), do: :idx_aex9_transfer
  def record(AeMdw.Db.Model.Aex9AccountPresence), do: :aex9_account_presence
  def record(AeMdw.Db.Model.IdxAex9AccountPresence), do: :idx_aex9_account_presence
  def record(AeMdw.Db.Model.ContractCall), do: :contract_call
  def record(AeMdw.Db.Model.ContractLog), do: :contract_log
  def record(AeMdw.Db.Model.DataContractLog), do: :data_contract_log
  def record(AeMdw.Db.Model.EvtContractLog), do: :evt_contract_log
  def record(AeMdw.Db.Model.IdxContractLog), do: :idx_contract_log
  def record(AeMdw.Db.Model.PlainName), do: :plain_name
  def record(AeMdw.Db.Model.AuctionBid), do: :auction_bid
  def record(AeMdw.Db.Model.Pointee), do: :pointee
  def record(AeMdw.Db.Model.AuctionExpiration), do: :expiration
  def record(AeMdw.Db.Model.ActiveNameExpiration), do: :expiration
  def record(AeMdw.Db.Model.InactiveNameExpiration), do: :expiration
  def record(AeMdw.Db.Model.ActiveName), do: :name
  def record(AeMdw.Db.Model.InactiveName), do: :name
  def record(AeMdw.Db.Model.AuctionOwner), do: :owner
  def record(AeMdw.Db.Model.ActiveNameOwner), do: :owner
  def record(AeMdw.Db.Model.ActiveOracleExpiration), do: :expiration
  def record(AeMdw.Db.Model.InactiveOracleExpiration), do: :expiration
  def record(AeMdw.Db.Model.ActiveOracle), do: :oracle
  def record(AeMdw.Db.Model.InactiveOracle), do: :oracle

  def table(:tx), do: AeMdw.Db.Model.Tx
  def table(:block), do: AeMdw.Db.Model.Block
  def table(:time), do: AeMdw.Db.Model.Time
  def table(:type), do: AeMdw.Db.Model.Type
  def table(:field), do: AeMdw.Db.Model.Field
  def table(:id_count), do: AeMdw.Db.Model.IdCount
  def table(:origin), do: AeMdw.Db.Model.Origin
  def table(:rev_origin), do: AeMdw.Db.Model.RevOrigin
  def table(:aex9_contract), do: AeMdw.Db.Model.Aex9Contract
  def table(:aex9_contract_symbol), do: AeMdw.Db.Model.Aex9ContractSymbol
  def table(:rev_aex9_contract), do: AeMdw.Db.Model.RevAex9Contract
  def table(:aex9_contract_pubkey), do: AeMdw.Db.Model.Aex9ContractPubkey
  def table(:aex9_transfer), do: AeMdw.Db.Model.Aex9Transfer
  def table(:rev_aex9_transfer), do: AeMdw.Db.Model.RevAex9Transfer
  def table(:idx_aex9_transfer), do: AeMdw.Db.Model.IdxAex9Transfer
  def table(:aex9_account_presence), do: AeMdw.Db.Model.Aex9AccountPresence
  def table(:idx_aex9_account_presence), do: AeMdw.Db.Model.IdxAex9AccountPresence
  def table(:contract_call), do: AeMdw.Db.Model.ContractCall
  def table(:contract_log), do: AeMdw.Db.Model.ContractLog
  def table(:data_contract_log), do: AeMdw.Db.Model.DataContractLog
  def table(:evt_contract_log), do: AeMdw.Db.Model.EvtContractLog
  def table(:idx_contract_log), do: AeMdw.Db.Model.IdxContractLog

  def defaults(:tx), do: @tx_defaults
  def defaults(:block), do: @block_defaults
  def defaults(:time), do: @time_defaults
  def defaults(:type), do: @type_defaults
  def defaults(:field), do: @field_defaults
  def defaults(:id_count), do: @id_count_defaults
  def defaults(:origin), do: @origin_defaults
  def defaults(:rev_origin), do: @rev_origin_defaults
  def defaults(:aex9_contract), do: @aex9_contract_defaults
  def defaults(:aex9_contract_symbol), do: @aex9_contract_symbol_defaults
  def defaults(:rev_aex9_contract), do: @rev_aex9_contract_defaults
  def defaults(:aex9_contract_pubkey), do: @aex9_contract_pubkey_defaults
  def defaults(:aex9_transfer), do: @aex9_transfer_defaults
  def defaults(:rev_aex9_transfer), do: @rev_aex9_transfer_defaults
  def defaults(:idx_aex9_transfer), do: @idx_aex9_transfer_defaults
  def defaults(:aex9_account_presence), do: @aex9_account_presence_defaults
  def defaults(:idx_aex9_account_presence), do: @idx_aex9_account_presence_defaults
  def defaults(:contract_call), do: @contract_call_defaults
  def defaults(:contract_log), do: @contract_log_defaults
  def defaults(:data_contract_log), do: @data_contract_log_defaults
  def defaults(:evt_contract_log), do: @evt_contract_log_defaults
  def defaults(:idx_contract_log), do: @idx_contract_log_defaults
  def defaults(:plain_name), do: @plain_name_defaults
  def defaults(:auction_bid), do: @auction_bid_defaults
  def defaults(:pointee), do: @pointee_defaults
  def defaults(:expiration), do: @expiration_defaults
  def defaults(:name), do: @name_defaults
  def defaults(:owner), do: @owner_defaults
  def defaults(:oracle), do: @oracle_defaults

  def write_count(model, delta) do
    total = id_count(model, :count)
    model = id_count(model, count: total + delta)
    :mnesia.write(AeMdw.Db.Model.IdCount, model, :write)
  end

  def update_count({_, _, _} = field_key, delta, empty_fn \\ fn -> :nop end) do
    case :mnesia.read(AeMdw.Db.Model.IdCount, field_key, :write) do
      [] -> empty_fn.()
      [model] -> write_count(model, delta)
    end
  end

  def incr_count({_, _, _} = field_key),
    do: update_count(field_key, 1, fn -> write_count(id_count(index: field_key, count: 0), 1) end)
end
