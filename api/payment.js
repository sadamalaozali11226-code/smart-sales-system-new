export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({
      error: "Method not allowed"
    });
  }

  try {
    const supabaseUrl =
      process.env.SUPABASE_URL;

    const supabaseKey =
      process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseKey) {
      return res.status(500).json({
        error: "Supabase configuration is missing"
      });
    }

    const {
      saleId,
      amount,
      paymentMethod,
      reference
    } = req.body || {};

    const parsedSaleId =
      Number(saleId);

    const paymentAmount =
      Number(amount);

    if (
      !Number.isInteger(parsedSaleId) ||
      parsedSaleId <= 0
    ) {
      return res.status(400).json({
        error: "Invalid saleId"
      });
    }

    if (
      !Number.isFinite(paymentAmount) ||
      paymentAmount <= 0
    ) {
      return res.status(400).json({
        error: "Invalid payment amount"
      });
    }

    const normalizedPaymentMethod =
      typeof paymentMethod === "string" &&
      paymentMethod.trim()
        ? paymentMethod.trim()
        : "cash";

    const normalizedReference =
      typeof reference === "string" &&
      reference.trim()
        ? reference.trim()
        : null;

    // Record payment atomically through PostgreSQL RPC
    const rpcResponse =
      await fetch(
        `${supabaseUrl}/rest/v1/rpc/record_sale_payment`,
        {
          method: "POST",
          headers: {
            apikey: supabaseKey,
            Authorization:
              `Bearer ${supabaseKey}`,
            "Content-Type":
              "application/json"
          },
          body: JSON.stringify({
            p_sale_id:
              parsedSaleId,
            p_amount:
              paymentAmount,
            p_payment_method:
              normalizedPaymentMethod,
            p_reference:
              normalizedReference
          })
        }
      );

    const responseText =
      await rpcResponse.text();

    let result = null;

    try {
      result = responseText
        ? JSON.parse(responseText)
        : null;
    } catch {
      result = null;
    }

    if (!rpcResponse.ok) {
      const rpcError =
        result?.message ||
        result?.error ||
        responseText ||
        "Failed to record payment";

      if (
        rpcError.includes("Sale not found")
      ) {
        return res.status(404).json({
          error: "Sale not found"
        });
      }

      if (
        rpcError.includes(
          "Cannot pay a cancelled sale"
        )
      ) {
        return res.status(400).json({
          error:
            "Cannot pay a cancelled sale"
        });
      }

      if (
        rpcError.includes(
          "Invoice is already fully paid"
        )
      ) {
        return res.status(400).json({
          error:
            "Invoice is already fully paid"
        });
      }

      if (
        rpcError.includes(
          "Payment exceeds remaining amount"
        )
      ) {
        return res.status(400).json({
          error: rpcError
        });
      }

      if (
        rpcError.includes(
          "Invalid payment amount"
        )
      ) {
        return res.status(400).json({
          error:
            "Invalid payment amount"
        });
      }

      console.error(
        "Payment RPC error:",
        rpcError
      );

      return res.status(500).json({
        error:
          "Failed to record payment"
      });
    }

    if (
      !result ||
      result.success !== true
    ) {
      console.error(
        "Invalid payment RPC response:",
        result
      );

      return res.status(500).json({
        error:
          "Invalid payment response"
      });
    }

    return res.status(200).json({
      success: true,
      saleId:
        result.sale_id,
      invoiceNumber:
        result.invoice_number,
      total:
        result.total,
      previousPaidAmount:
        result.previousPaidAmount,
      paymentAmount:
        result.paymentAmount,
      paidAmount:
        result.paidAmount,
      remainingAmount:
        result.remainingAmount,
      paymentStatus:
        result.paymentStatus,
      paymentMethod:
        result.paymentMethod,
      reference:
        result.reference,
      paymentId:
        result.paymentId
    });

  } catch (error) {
    console.error(
      "Payment error:",
      error
    );

    return res.status(500).json({
      error:
        "Failed to record payment"
    });
  }
}
