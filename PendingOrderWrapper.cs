using System;
using TradingPlatform.BusinessLayer;

namespace TradingPlatform.BusinessLayer
{
    /// <summary>
    /// Reusable helper class to wrap pending order execution for Quantower strategies.
    /// Dynamically routes orders to Stop, Market, or Limit based on the distance between 
    /// the target breakout level (entryPrice) and the current market Bid/Ask price.
    /// </summary>
    public class PendingOrderWrapper
    {
        private readonly Strategy strategy;

        /// <summary>
        /// Initializes a new instance of the PendingOrderWrapper class.
        /// </summary>
        /// <param name="strategy">The strategy instance calling this wrapper (used for logging).</param>
        public PendingOrderWrapper(Strategy strategy)
        {
            this.strategy = strategy;
        }

        /// <summary>
        /// Places a robust Buy order using adaptive execution (Stop, Market, or Limit).
        /// </summary>
        public TradingOperationResult BuyPending(
            Account account,
            Symbol symbol,
            double lot,
            double entryPrice,
            int slTicks,
            int tpTicks,
            int maxChaseTicks,
            string comment,
            TimeInForce timeInForce = TimeInForce.GTC)
        {
            if (symbol == null)
                throw new ArgumentNullException(nameof(symbol), "Symbol cannot be null.");

            double tickSize = symbol.TickSize;
            double currentAsk = symbol.Ask;
            string orderType = OrderType.Stop;
            double limitPrice = 0;
            double triggerPrice = 0;
            double entryReferencePrice = entryPrice; // Reference price for dynamic SL/TP

            if (entryPrice > currentAsk)
            {
                // State 3: Stop Order (Normal breakout waiting)
                orderType = OrderType.Stop;
                triggerPrice = entryPrice;
                entryReferencePrice = entryPrice;
            }
            else if (currentAsk - entryPrice <= maxChaseTicks * tickSize)
            {
                // State 1: Market Order (Within Chase Zone - execute immediately to avoid missing wave)
                orderType = OrderType.Market;
                entryReferencePrice = currentAsk;
                this.strategy.Log($"[{comment}] Price slightly past entry (Ask={currentAsk} >= Entry={entryPrice}, within {maxChaseTicks} ticks). Placing BUY MARKET order.");
            }
            else
            {
                // State 2: Limit Order (Price has run too far - place limit at original breakout and wait for pullback)
                orderType = OrderType.Limit;
                limitPrice = entryPrice;
                entryReferencePrice = entryPrice;
                this.strategy.Log($"[{comment}] Price is too far past entry (Ask={currentAsk} >= Entry={entryPrice}, > {maxChaseTicks} ticks). Placing BUY LIMIT at original entry to wait for pullback.");
            }

            // Risk Sizing based on the correct reference price (either entryPrice or currentAsk)
            double sl = entryReferencePrice - slTicks * tickSize;
            double tp = tpTicks > 0 ? (entryReferencePrice + tpTicks * tickSize) : 0;
            sl = Math.Round(sl / tickSize) * tickSize;
            tp = Math.Round(tp / tickSize) * tickSize;

            var request = new PlaceOrderRequestParameters
            {
                Account = account,
                Symbol = symbol,
                Side = Side.Buy,
                OrderTypeId = orderType,
                Quantity = lot,
                Price = limitPrice,
                TriggerPrice = triggerPrice,
                StopLoss = SlTpHolder.CreateSL(sl, PriceMeasurement.Absolute),
                TakeProfit = tp > 0 ? SlTpHolder.CreateTP(tp, PriceMeasurement.Absolute) : null,
                Comment = comment,
                TimeInForce = timeInForce
            };

            return Core.Instance.PlaceOrder(request);
        }

        /// <summary>
        /// Places a robust Sell order using adaptive execution (Stop, Market, or Limit).
        /// </summary>
        public TradingOperationResult SellPending(
            Account account,
            Symbol symbol,
            double lot,
            double entryPrice,
            int slTicks,
            int tpTicks,
            int maxChaseTicks,
            string comment,
            TimeInForce timeInForce = TimeInForce.GTC)
        {
            if (symbol == null)
                throw new ArgumentNullException(nameof(symbol), "Symbol cannot be null.");

            double tickSize = symbol.TickSize;
            double currentBid = symbol.Bid;
            string orderType = OrderType.Stop;
            double limitPrice = 0;
            double triggerPrice = 0;
            double entryReferencePrice = entryPrice; // Reference price for dynamic SL/TP

            if (entryPrice < currentBid)
            {
                // State 3: Stop Order (Normal breakout waiting)
                orderType = OrderType.Stop;
                triggerPrice = entryPrice;
                entryReferencePrice = entryPrice;
            }
            else if (entryPrice - currentBid <= maxChaseTicks * tickSize)
            {
                // State 1: Market Order (Within Chase Zone - execute immediately to avoid missing wave)
                orderType = OrderType.Market;
                entryReferencePrice = currentBid;
                this.strategy.Log($"[{comment}] Price slightly past entry (Bid={currentBid} <= Entry={entryPrice}, within {maxChaseTicks} ticks). Placing SELL MARKET order.");
            }
            else
            {
                // State 2: Limit Order (Price has run too far - place limit at original breakout and wait for pullback)
                orderType = OrderType.Limit;
                limitPrice = entryPrice;
                entryReferencePrice = entryPrice;
                this.strategy.Log($"[{comment}] Price is too far past entry (Bid={currentBid} <= Entry={entryPrice}, > {maxChaseTicks} ticks). Placing SELL LIMIT at original entry to wait for pullback.");
            }

            // Risk Sizing based on the correct reference price (either entryPrice or currentBid)
            double sl = entryReferencePrice + slTicks * tickSize;
            double tp = tpTicks > 0 ? (entryReferencePrice - tpTicks * tickSize) : 0;
            sl = Math.Round(sl / tickSize) * tickSize;
            tp = Math.Round(tp / tickSize) * tickSize;

            var request = new PlaceOrderRequestParameters
            {
                Account = account,
                Symbol = symbol,
                Side = Side.Sell,
                OrderTypeId = orderType,
                Quantity = lot,
                Price = limitPrice,
                TriggerPrice = triggerPrice,
                StopLoss = SlTpHolder.CreateSL(sl, PriceMeasurement.Absolute),
                TakeProfit = tp > 0 ? SlTpHolder.CreateTP(tp, PriceMeasurement.Absolute) : null,
                Comment = comment,
                TimeInForce = timeInForce
            };

            return Core.Instance.PlaceOrder(request);
        }
    }
}
