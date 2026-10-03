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

    // Get sale
    const saleResponse =
      await fetch(
        `${supabaseUrl}/rest/v1/sales?id=eq.${parsedSaleId}&select=id,invoice_number,total,payment_status,status`,
        {
          headers: {
            apikey: supabaseKey,
            Authorization:
              `Bearer ${supabaseKey}`
          }
        }
      );

    if (!saleResponse.ok) {
      throw new Error(
        "Failed to load sale"
      );
    }

    const sales =
      await saleResponse.json();

    if (!sales.length) {
      return res.status(404).json({
        error: "Sale not found"
      });
    }

    const sale = sales[0];

    if (sale.status === "cancelled") {
      return res.status(400).json({
        error: "Cannot pay a cancelled sale"
      });
    }

    const total =
      Number(sale.total);

    if (
      !Number.isFinite(total) ||
      total <= 0
    ) {
      return res.status(400).json({
        error: "Invalid sale total"
      });
    }

    // Get previous payments
    const paymentsResponse =
      await fetch(
        `${supabaseUrl}/rest/v1/payments?sale_id=eq.${parsedSaleId}&select=id,amount,payment_method,reference,paid_at&order=paid_at.asc`,
        {
          headers: {
            apikey: supabaseKey,
            Authorization:
              `Bearer ${supabaseKey}`
          }
        }
      );

    if (!paymentsResponse.ok) {
      throw new Error(
        "Failed to load previous payments"
      );
    }

    const payments =
      await paymentsResponse.json();

    const paidBefore =
      payments.reduce(
        (sum, payment) =>
          sum + Number(payment.amount || 0),
        0
      );

    const remainingBefore =
      Math.max(
        total - paidBefore,
        0
      );

    if (remainingBefore <= 0) {
      return res.status(400).json({
        error: "Invoice is already fully paid"
      });
    }

    if (
      paymentAmount >
      remainingBefore
    ) {
      return res.status(400).json({
        error:
          `Payment exceeds remaining amount. Remaining: ${remainingBefore}`
      });
    }

    // Insert payment
    const paymentResponse =
      await fetch(
        `${supabaseUrl}/rest/v1/payments`,
        {
          method: "POST",
          headers: {
            apikey: supabaseKey,
            Authorization:
              `Bearer ${supabaseKey}`,
            "Content-Type":
              "application/json",
            Prefer:
              "return=representation"
          },
          body: JSON.stringify({
            sale_id: parsedSaleId,
            amount: paymentAmount,
            payment_method:
              paymentMethod || "cash",
            reference:
              reference || null,
            paid_at:
              new Date().toISOString()
          })
        }
      );

    if (!paymentResponse.ok) {
      const errorText =
        await paymentResponse.text();

      throw new Error(
        errorText ||
        "Failed to record payment"
      );
    }

    const insertedPayments =
      await paymentResponse.json();

    const insertedPayment =
      insertedPayments[0];

    const paidAmount =
      paidBefore +
      paymentAmount;

    const remainingAmount =
      Math.max(
        total - paidAmount,
        0
      );

    let paymentStatus =
      "unpaid";

    if (remainingAmount <= 0.001) {
      paymentStatus = "paid";
    } else if (paidAmount > 0) {
      paymentStatus = "partial";
    }

    // Update sale payment status
    const updateResponse =
      await fetch(
        `${supabaseUrl}/rest/v1/sales?id=eq.${parsedSaleId}`,
        {
          method: "PATCH",
          headers: {
            apikey: supabaseKey,
            Authorization:
              `Bearer ${supabaseKey}`,
            "Content-Type":
              "application/json",
            Prefer:
              "return=minimal"
          },
          body: JSON.stringify({
            payment_status:
              paymentStatus
          })
        }
      );

    if (!updateResponse.ok) {
      // Roll back inserted payment
      if (insertedPayment?.id) {
        await fetch(
          `${supabaseUrl}/rest/v1/payments?id=eq.${insertedPayment.id}`,
          {
            method: "DELETE",
            headers: {
              apikey: supabaseKey,
              Authorization:
                `Bearer ${supabaseKey}`
            }
          }
        );
      }

      throw new Error(
        "Failed to update sale payment status"
      );
    }

    return res.status(200).json({
      success: true,
      saleId: parsedSaleId,
      invoiceNumber:
        sale.invoice_number,
      total,
      previousPaidAmount:
        paidBefore,
      paymentAmount,
      paidAmount,
      remainingAmount,
      paymentStatus,
      paymentMethod:
        paymentMethod || "cash",
      reference:
        reference || null,
      payment:
        insertedPayment || null
    });

  } catch (error) {
    console.error(
      "Payment error:",
      error
    );

    return res.status(500).json({
      error:
        error.message ||
        "Failed to record payment"
    });
  }
}
