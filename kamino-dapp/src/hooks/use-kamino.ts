import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { contracts } from "@/config/contracts";
import { formatUnits, parseUnits } from "viem";
import { useState } from "react";
import { useToast } from "@/components/ui/use-toast";
import { erc20Abi } from "viem";

export function useKamino() {
  const { address } = useAccount();
  const { toast } = useToast();
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");

  const { data: totalAssets, isLoading: isTotalAssetsLoading, refetch: refetchTotalAssets } = useReadContract({
    ...contracts.kaminoVault,
    functionName: "totalAssets",
  });

  const { data: userBalance, isLoading: isUserBalanceLoading, refetch: refetchUserBalance } = useReadContract({
    ...contracts.kaminoVault,
    functionName: "balanceOf",
    args: [address],
    query: {
      enabled: !!address,
    },
  });

  const { data: asset, isLoading: isAssetLoading } = useReadContract({
    ...contracts.kaminoVault,
    functionName: 'asset',
  });

  const { data: decimals, isLoading: isDecimalsLoading } = useReadContract({
    abi: erc20Abi,
    address: asset,
    functionName: 'decimals',
    query: {
      enabled: !!asset,
    },
  });

  const { data: assetSymbol, isLoading: isAssetSymbolLoading } = useReadContract({
    abi: erc20Abi,
    address: asset,
    functionName: 'symbol',
    query: {
      enabled: !!asset,
    },
  });

  const { data: userAssetBalance, isLoading: isUserAssetBalanceLoading, refetch: refetchUserAssetBalance } = useReadContract({
    abi: erc20Abi,
    address: asset,
    functionName: 'balanceOf',
    args: [address!],
    query: {
      enabled: !!address && !!asset,
    },
  });

  const parsedDepositAmount = depositAmount && decimals ? parseUnits(depositAmount, decimals) : 0n;

  const { data: allowance, isLoading: isAllowanceLoading, refetch: refetchAllowance } = useReadContract({
    abi: erc20Abi,
    address: asset,
    functionName: 'allowance',
    args: [address!, contracts.kaminoVault.address],
    query: {
      enabled: !!address && !!asset,
    },
  });

  const { data: approveHash, writeContract: approve, isPending: isApproving } = useWriteContract();
  const { data: depositHash, writeContract: deposit, isPending: isDepositing } = useWriteContract();
  const { data: withdrawHash, writeContract: withdraw, isPending: isWithdrawing } = useWriteContract();

  const { isLoading: isApproveConfirming } = useWaitForTransactionReceipt({
    hash: approveHash,
    onSuccess: (receipt) => {
      toast({ title: "Approval Successful", description: `Transaction confirmed: ${receipt.transactionHash}` });
      refetchAllowance();
      refetchUserBalance();
      refetchUserAssetBalance();
    },
    onError: (error) => {
      toast({ title: "Approval Failed", description: error.message, variant: "destructive" });
    }
  });

  const { isLoading: isDepositConfirming } = useWaitForTransactionReceipt({
    hash: depositHash,
    onSuccess: (receipt) => {
      toast({ title: "Deposit Successful", description: `Transaction confirmed: ${receipt.transactionHash}` });
      refetchTotalAssets();
      refetchUserBalance();
      refetchUserAssetBalance();
      setDepositAmount("");
    },
    onError: (error) => {
      toast({ title: "Deposit Failed", description: error.message, variant: "destructive" });
    }
  });

  const { isLoading: isWithdrawConfirming } = useWaitForTransactionReceipt({
    hash: withdrawHash,
    onSuccess: (receipt) => {
      toast({ title: "Withdrawal Successful", description: `Transaction confirmed: ${receipt.transactionHash}` });
      refetchTotalAssets();
      refetchUserBalance();
      refetchUserAssetBalance();
      setWithdrawAmount("");
    },
    onError: (error) => {
      toast({ title: "Withdrawal Failed", description: error.message, variant: "destructive" });
    }
  });

  const parsedWithdrawAmount = withdrawAmount && decimals ? parseUnits(withdrawAmount, decimals) : 0n;
  const needsApproval = allowance !== undefined && parsedDepositAmount > allowance;

  const handleApprove = () => {
    if (!asset) return;
    approve({
      abi: erc20Abi,
      address: asset,
      functionName: 'approve',
      args: [contracts.kaminoVault.address, parsedDepositAmount],
    });
  };

  const handleDeposit = () => {
    if (!address) return;
    deposit({
      ...contracts.kaminoVault,
      functionName: 'deposit',
      args: [parsedDepositAmount, address],
    });
  };

  const handleWithdraw = () => {
    if (!address) return;
    withdraw({
      ...contracts.kaminoVault,
      functionName: 'withdraw',
      args: [parsedWithdrawAmount, address, address],
    });
  };

  const formattedTotalAssets = totalAssets && decimals ? formatUnits(totalAssets, decimals) : "0";
  const formattedUserBalance = userBalance && decimals ? formatUnits(userBalance, decimals) : "0";
  const formattedUserAssetBalance = userAssetBalance && decimals ? formatUnits(userAssetBalance, decimals) : "0";

  return {
    totalAssets: formattedTotalAssets,
    userBalance: formattedUserBalance,
    userAssetBalance: formattedUserAssetBalance,
    assetSymbol: assetSymbol || "Token",
    asset,
    isLoading: isTotalAssetsLoading || isUserBalanceLoading || isAssetLoading || isDecimalsLoading || isAllowanceLoading || isAssetSymbolLoading || isUserAssetBalanceLoading,
    depositAmount,
    setDepositAmount,
    withdrawAmount,
    setWithdrawAmount,
    needsApproval,
    handleApprove,
    handleDeposit,
    handleWithdraw,
    isApproving,
    isApproveConfirming,
    isDepositing,
    isDepositConfirming,
    isWithdrawing,
    isWithdrawConfirming,
  };
}