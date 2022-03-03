defmodule AeMdw.Db.ContractCallMutation do
  @moduledoc """
  Processes contract_call_tx.
  """

  alias AeMdw.Contract
  alias AeMdw.Db.Contract, as: DBContract
  alias AeMdw.Sync.AsyncTasks
  alias AeMdw.Txs

  @derive AeMdw.Db.Mutation
  defstruct [
    :contract_pk,
    :caller_pk,
    :create_txi,
    :txi,
    :fun_arg_res,
    :call_rec,
    :aex9_meta_info
  ]

  @typep pubkey() :: AeMdw.Node.Db.pubkey()
  @typep txi_option() :: Txs.txi() | -1

  @opaque t() :: %__MODULE__{
            contract_pk: pubkey(),
            caller_pk: pubkey(),
            create_txi: txi_option(),
            txi: Txs.txi(),
            fun_arg_res: Contract.fun_arg_res_or_error(),
            aex9_meta_info: Contract.aex9_meta_info() | nil,
            call_rec: Contract.call()
          }

  @spec new(
          pubkey(),
          pubkey(),
          txi_option(),
          Txs.txi(),
          Contract.fun_arg_res_or_error(),
          Contract.aex9_meta_info() | nil,
          Contract.call()
        ) :: t()
  def new(contract_pk, caller_pk, create_txi, txi, fun_arg_res, aex9_meta_info, call_rec) do
    %__MODULE__{
      contract_pk: contract_pk,
      caller_pk: caller_pk,
      create_txi: create_txi,
      txi: txi,
      fun_arg_res: fun_arg_res,
      aex9_meta_info: aex9_meta_info,
      call_rec: call_rec
    }
  end

  @spec mutate(t()) :: :ok
  def mutate(%__MODULE__{
        contract_pk: contract_pk,
        caller_pk: caller_pk,
        create_txi: create_txi,
        txi: txi,
        fun_arg_res: fun_arg_res,
        aex9_meta_info: aex9_meta_info,
        call_rec: call_rec
      }) do
    DBContract.call_write(create_txi, txi, fun_arg_res)
    DBContract.logs_write(create_txi, txi, call_rec)

    if Contract.is_aex9?(contract_pk) and Contract.is_aex9_successful_call?(fun_arg_res) do
      %{function: method_name, arguments: method_args} = fun_arg_res

      if not Contract.is_non_stateful_aex9_function?(method_name) do
        update_aex9_presence(
          contract_pk,
          caller_pk,
          txi,
          method_name,
          method_args
        )
      end
    end

    if aex9_meta_info do
      DBContract.aex9_creation_write(aex9_meta_info, contract_pk, caller_pk, txi)
    end

    :ok
  end

  #
  # Private functions
  #
  defp update_aex9_presence(contract_pk, caller_pk, txi, method_name, method_args) do
    updated? =
      update_aex9_presence_and_balance(method_name, method_args, contract_pk, caller_pk, txi)

    if not updated? do
      AsyncTasks.Producer.enqueue(:update_aex9_presence, [contract_pk])
    end
  end

  defp update_aex9_presence_and_balance(
         "burn",
         [%{type: :int, value: value}],
         contract_pk,
         caller_pk,
         txi
       ) do
    DBContract.aex9_burn_balance(contract_pk, caller_pk, value)
    DBContract.aex9_write_presence(contract_pk, txi, caller_pk)
    true
  end

  defp update_aex9_presence_and_balance("swap", [], contract_pk, caller_pk, txi) do
    DBContract.aex9_delete_balance(contract_pk, caller_pk)
    DBContract.aex9_write_presence(contract_pk, txi, caller_pk)
    true
  end

  defp update_aex9_presence_and_balance(
         "mint",
         [
           %{type: :address, value: to_pk},
           %{type: :int, value: value}
         ],
         contract_pk,
         _caller_pk,
         txi
       ) do
    DBContract.aex9_mint_balance(contract_pk, to_pk, value)
    DBContract.aex9_write_presence(contract_pk, txi, to_pk)
  end

  defp update_aex9_presence_and_balance(method_name, method_args, contract_pk, caller_pk, txi) do
    with {from_pk, to_pk, value} <-
           Contract.get_aex9_transfer(caller_pk, method_name, method_args),
         DBContract.aex9_transfer_balance(contract_pk, from_pk, to_pk, value) do
      DBContract.aex9_write_presence(contract_pk, txi, from_pk)
      DBContract.aex9_write_presence(contract_pk, txi, to_pk)
      true
    else
      _nil_or_error ->
        DBContract.aex9_invalidate_balances(contract_pk)
        false
    end
  end
end
