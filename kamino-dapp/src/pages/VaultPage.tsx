import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useKamino } from "@/hooks/use-kamino";
import { Skeleton } from "@/components/ui/skeleton";

export function VaultPage() {
  const {
    totalAssets,
    userBalance,
    isLoading,
    depositAmount,
    setDepositAmount,
    needsApproval,
    handleApprove,
    handleDeposit,
    isApproving,
    isApproveConfirming,
    isDepositing,
    isDepositConfirming,
    withdrawAmount,
    setWithdrawAmount,
    handleWithdraw,
    isWithdrawing,
    isWithdrawConfirming,
  } = useKamino();

  return (
    <div className="container mx-auto p-4">
      <div className="flex justify-between items-center mb-4">
        <h1 className="text-2xl font-bold">EVM Kamino Vault</h1>
      </div>

      <Card className="mb-4">
        <CardHeader>
          <CardTitle>Vault Stats</CardTitle>
          <CardDescription>USDC/WETH Pool</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <p className="text-sm text-muted-foreground">Total Assets</p>
              {isLoading ? (
                <Skeleton className="h-6 w-32" />
              ) : (
                <p className="text-lg font-semibold">${totalAssets}</p>
              )}
            </div>
            <div>
              <p className="text-sm text-muted-foreground">Your Balance</p>
              {isLoading ? (
                <Skeleton className="h-6 w-24" />
              ) : (
                <p className="text-lg font-semibold">${userBalance}</p>
              )}
            </div>
            <div>
              <p className="text-sm text-muted-foreground">Current APR</p>
              <p className="text-lg font-semibold">12.34%</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <Tabs defaultValue="deposit" className="w-full">
        <TabsList className="grid w-full grid-cols-2">
          <TabsTrigger value="deposit">Deposit</TabsTrigger>
          <TabsTrigger value="withdraw">Withdraw</TabsTrigger>
        </TabsList>
        <TabsContent value="deposit">
          <Card>
            <CardHeader>
              <CardTitle>Deposit</CardTitle>
              <CardDescription>
                Deposit assets into the vault to start earning yield.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-2">
              <div className="space-y-1">
                <Label htmlFor="deposit-amount">Amount</Label>
                <Input
                  id="deposit-amount"
                  type="number"
                  placeholder="0.0"
                  value={depositAmount}
                  onChange={(e) => setDepositAmount(e.target.value)}
                />
              </div>
            </CardContent>
            <CardFooter>
              {needsApproval ? (
                <Button
                  onClick={handleApprove}
                  disabled={isApproving || isApproveConfirming}
                >
                  {isApproving || isApproveConfirming ? "Approving..." : "Approve"}
                </Button>
              ) : (
                <Button
                  onClick={handleDeposit}
                  disabled={isDepositing || isDepositConfirming || !depositAmount}
                >
                  {isDepositing || isDepositConfirming ? "Depositing..." : "Deposit"}
                </Button>
              )}
            </CardFooter>
          </Card>
        </TabsContent>
        <TabsContent value="withdraw">
          <Card>
            <CardHeader>
              <CardTitle>Withdraw</CardTitle>
              <CardDescription>
                Withdraw your assets and realize your earnings.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-2">
              <div className="space-y-1">
                <Label htmlFor="withdraw-amount">Amount</Label>
                <Input
                  id="withdraw-amount"
                  type="number"
                  placeholder="0.0"
                  value={withdrawAmount}
                  onChange={(e) => setWithdrawAmount(e.target.value)}
                />
              </div>
            </CardContent>
            <CardFooter>
              <Button
                variant="secondary"
                onClick={handleWithdraw}
                disabled={isWithdrawing || isWithdrawConfirming || !withdrawAmount}
              >
                {isWithdrawing || isWithdrawConfirming ? "Withdrawing..." : "Withdraw"}
              </Button>
            </CardFooter>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}