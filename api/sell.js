export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({
      error: "Method not allowed"
    });
  }

  const SUPABASE_URL = process.env.SUPABASE_URL;
  const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!SUPABASE_URL || !SUPABASE_KEY) {
    return res.status(500).json({
      error: "Supabase environment variables are missing"
    });
  }

  const id = Number(req.body?.id);

  const customerId =
    req.body?.customerId === undefined ||
    req.body?.customerId === null ||
    req.body?.customerId === ""
      ? null
      : Number(req.body.customerId);

  const paymentStatus =
    req.body?.paymentStatus === undefined ||
    req.body?.paymentStatus === null ||
    req.body?.paymentStatus === ""
      ? null
      : String(req.body.paymentStatus).trim().toLowerCase();

  const paidAmount =
    req.body?.paidAmount === undefined ||
    req.body?.paidAmount === null ||
    req.body?.paidAmount === ""
      ? null
      : Number(req.body.paidAmount);

  const paymentMethod =
    req.body?.paymentMethod === undefined ||
    req.body?.paymentMethod === null
      ? null
      : String(req.body.paymentMethod).trim();

  const reference =
    req.body?.reference === undefined ||
    req.body?.reference === null
      ? null
      : String(req.body.reference).trim();

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({
      error: "Invalid product id"
    });
  }

  if (
    customerId !== null &&
    (!Number.isInteger(customerId) || customerId <= 0)
  ) {
    return res.status(400).json({
      error: "Invalid customer id"
    });
  }

  if (
    paymentStatus === null ||
    !["paid", "partial", "unpaid"].includes(paymentStatus)
  ) {
    return res.status(400).json({
      error: "Invalid payment status"
    });
  }

  if (
    paidAmount === null ||
    !Number.isFinite(paidAmount) ||
    paidAmount < 0
  ) {
    return res.status(400).json({
      error: "Invalid paid amount"
    });
  }

  if (
    paymentStatus === "partial" &&
    customerId === null
  ) {
    return res.status(400).json({
      error: "Customer is required for partial payment"
    });
  }

  if (
    paymentStatus === "unpaid" &&
    customerId === null
  ) {
    return res.status(400).json({
      error: "Customer is required for unpaid sales"
    });
  }

  if (
    paymentStatus === "unpaid" &&
    paidAmount !== 0
  ) {
    return res.status(400).json({
      error: "Unpaid sale must have zero paid amount"
    });
  }

  if (
    paymentStatus === "partial" &&
    paidAmount <= 0
  ) {
    return res.status(400).json({
      error: "Partial payment must be greater than zero"
    });
  }

  try {
    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/rpc/record_product_sale_with_payment`,
      {
        method: "POST",
        headers: {
          apikey: SUPABASE_KEY,
          Authorization: `Bearer ${SUPABASE_KEY}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          p_product_id: id,
          p_customer_id: customerId,
          p_payment_status: paymentStatus,
          p_paid_amount: paidAmount,
          p_payment_method: paymentMethod,
          p_reference: reference
        })
      }
    );

    const text = await response.text();

    let data;

    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = text;
    }

    if (!response.ok) {
      console.error(
        "SUPABASE SALE WITH PAYMENT ERROR:",
        data
      );

      const errorMessage =
        typeof data === "object" && data !== null
          ? data.message ||
            data.error ||
            data.hint ||
            JSON.stringify(data)
          : String(data);

      const normalizedError =
        errorMessage.toLowerCase();

      if (
        normalizedError.includes("product not found")
      ) {
        return res.status(404).json({
          error: "Product not found"
        });
      }

      if (
        normalizedError.includes("out of stock")
      ) {
        return res.status(400).json({
          error: "Product is out of stock"
        });
      }

      if (
        normalizedError.includes("customer not found")
      ) {
        return res.status(404).json({
          error: "Customer not found"
        });
      }

      if (
        normalizedError.includes(
          "customer is required for unpaid or partial sales"
        )
      ) {
        return res.status(400).json({
          error:
            "Customer is required for unpaid or partial sales"
        });
      }

      if (
        normalizedError.includes(
          "customer is required for partial payment"
        )
      ) {
        return res.status(400).json({
          error:
            "Customer is required for partial payment"
        });
      }

      if (
        normalizedError.includes(
          "paid amount must equal sale total"
        )
      ) {
        return res.status(400).json({
          error:
            "Paid amount must equal sale total"
        });
      }

      if (
        normalizedError.includes(
          "partial payment must be greater than zero and less than total"
        )
      ) {
        return res.status(400).json({
          error:
            "Partial payment must be greater than zero and less than total"
        });
      }

      if (
        normalizedError.includes(
          "unpaid sale must have zero paid amount"
        )
      ) {
        return res.status(400).json({
          error:
            "Unpaid sale must have zero paid amount"
        });
      }

      if (
        normalizedError.includes(
          "invalid payment status"
        )
      ) {
        return res.status(400).json({
          error: "Invalid payment status"
        });
      }

      if (
        normalizedError.includes(
          "invalid paid amount"
        )
      ) {
        return res.status(400).json({
          error: "Invalid paid amount"
        });
      }

      return res.status(500).json({
        error: "Failed to record sale",
        details: errorMessage
      });
    }

    if (
      !data ||
      data.success !== true
    ) {
      return res.status(500).json({
        error: "Sale was not recorded correctly"
      });
    }

    return res.status(200).json({
      success: true,

      saleId:
        data.sale_id,

      invoiceNumber:
        data.invoice_number,

      customerId:
        data.customer_id === null ||
        data.customer_id === undefined
          ? null
          : Number(data.customer_id),

      product: {
        id:
          data.product_id,

        name:
          data.product_name,

        price:
          Number(data.price),

        quantity:
          Number(data.quantity)
      },

      soldQuantity:
        Number(data.sold_quantity || 1),

      total:
        Number(data.total || 0),

      paidAmount:
        Number(data.paid_amount || 0),

      remainingAmount:
        Number(data.remaining_amount || 0),

      paymentStatus:
        data.payment_status,

      paymentMethod:
        paymentMethod || null,

      reference:
        reference || null
    });

  } catch (error) {
    console.error(
      "SELL WITH PAYMENT ERROR:",
      error
    );

    return res.status(500).json({
      error: "Failed to record sale",
      details: error.message
    });
  }
}
