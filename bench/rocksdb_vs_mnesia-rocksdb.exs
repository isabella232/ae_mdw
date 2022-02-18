alias AeMdw.Database
alias AeMdw.Db.Model
alias AeMdw.Db.ModelFixtures
alias AeMdw.Db.RocksDb
alias AeMdw.Db.WriteTxnMutation
alias AeMdw.Db.WriteMutation

:ok = RocksDb.close()
Process.sleep(1000)
{:ok, _} = File.rm_rf("test_data.db")
System.cmd("sync", [])
:ok = RocksDb.open()

ModelFixtures.init()
blocks = for _i <- 1..10_000, do: ModelFixtures.new_block()
txn_mutations = for m_block <- blocks, do: WriteTxnMutation.new(Model.Block, m_block)
mutations = for m_block <- blocks, do: WriteMutation.new(Model.Block, m_block)

rocksdb_mutations = Enum.take(txn_mutations, 100)
mnesia_mutations = Enum.take(mutations, 100)

Benchee.run(%{
    rocksdb_txn_100: fn -> Database.commit(rocksdb_mutations) end,
    mensia_write_100: fn -> Database.transaction(mnesia_mutations) end,
  }, parallel: 1
)

:ok = RocksDb.close()
Process.sleep(1000)
{:ok, _} = File.rm_rf("test_data.db")
System.cmd("sync", [])
:ok = RocksDb.open()

rocksdb_mutations = Enum.take(txn_mutations, 1000)
mnesia_mutations = Enum.take(mutations, 1000)

Benchee.run(%{
  rocksdb_txn_1k: fn -> Database.commit(rocksdb_mutations) end,
  mensia_write_1k: fn -> Database.transaction(mnesia_mutations) end,
  },
  memory_time: 1
)

:ok = RocksDb.close()
Process.sleep(1000)
{:ok, _} = File.rm_rf("test_data.db")
System.cmd("sync", [])
:ok = RocksDb.open()

rocksdb_mutations = Enum.take(txn_mutations, 10000)
mnesia_mutations = Enum.take(mutations, 10000)

Benchee.run(
  %{
    rocksdb_txn_10k: fn -> Database.commit(rocksdb_mutations) end,
    mensia_write_10k: fn -> Database.transaction(mnesia_mutations) end,
  },
  memory_time: 1
)
