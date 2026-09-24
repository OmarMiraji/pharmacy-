# Phyimacy Firestore Schema

All documents should include `createdAt` and `updatedAt` where applicable. Store dates as Firestore `Timestamp` values and money as integer minor units (for example, cents) or a clearly defined decimal convention.

## Collections

### `users/{userId}`

- `displayName`: string
- `email`: string, matching the Firebase Authentication email
- `role`: `admin | pharmacist | cashier | storekeeper`
- `permissions`: map of permission keys to boolean values
- `phone`: string, optional
- `isActive`: boolean
- `createdAt`: timestamp
- `updatedAt`: timestamp

Create credentials in Firebase Authentication, not in application code or
Firestore. Only an admin can change roles, permission flags, or account status.
A user can update only their own display name and phone number.

### `categories/{categoryId}`

- `name`: string
- `description`: string, optional
- `isActive`: boolean
- `createdAt`: timestamp
- `updatedAt`: timestamp

### `suppliers/{supplierId}`

- `name`: string
- `phone`: string, optional
- `email`: string, optional
- `address`: string, optional
- `isActive`: boolean
- `createdAt`: timestamp
- `updatedAt`: timestamp

### `medicines/{medicineId}`

- `name`: string
- `genericName`: string, optional
- `sku`: string
- `barcode`: string, optional
- `categoryId`: string
- `supplierId`: string, optional
- `unit`: string
- `purchasePriceMinor`: number
- `sellingPriceMinor`: number
- `quantityOnHand`: number
- `reorderLevel`: number
- `requiresPrescription`: boolean
- `isActive`: boolean
- `createdAt`: timestamp
- `updatedAt`: timestamp

### `medicine_batches/{batchId}`

Keep stock by batch so expiry tracking and FEFO (first expiry, first out) remain possible.

- `medicineId`: string
- `batchNumber`: string
- `expiryDate`: timestamp
- `quantityOnHand`: number
- `unitCostMinor`: number
- `sellingPriceMinor`: number, optional
- `supplierId`: string, optional
- `purchaseId`: string, optional
- `isActive`: boolean
- `createdAt`: timestamp
- `updatedAt`: timestamp

### `purchases/{purchaseId}`

- `supplierId`: string
- `invoiceNumber`: string, optional
- `status`: `draft | received | cancelled`
- `subtotalMinor`: number
- `taxMinor`: number
- `totalMinor`: number
- `receivedAt`: timestamp, optional
- `createdBy`: string
- `createdAt`: timestamp
- `updatedAt`: timestamp

### `purchases/{purchaseId}/items/{itemId}`

- `medicineId`: string
- `quantity`: number
- `unitCostMinor`: number
- `totalMinor`: number
- `batchNumber`: string, optional
- `expiryDate`: timestamp, optional

### `sales/{saleId}`

- `receiptNumber`: string
- `customerId`: string, optional
- `status`: `completed | voided | refunded`
- `paymentMethod`: `cash | card | mobile_money | mixed`
- `subtotalMinor`: number
- `discountMinor`: number
- `taxMinor`: number
- `totalMinor`: number
- `soldBy`: string
- `createdAt`: timestamp
- `updatedAt`: timestamp

### `sales/{saleId}/items/{itemId}`

- `medicineId`: string
- `medicineName`: string
- `quantity`: number
- `unitPriceMinor`: number
- `totalMinor`: number
- `batchNumber`: string, optional

### `stock_movements/{movementId}`

- `medicineId`: string
- `type`: `purchase | sale | adjustment | return | damage`
- `quantityChange`: number
- `referenceId`: string, optional
- `reason`: string, optional
- `createdBy`: string
- `createdAt`: timestamp

### `customers/{customerId}`

- `name`: string
- `phone`: string, optional
- `email`: string, optional
- `createdAt`: timestamp
- `updatedAt`: timestamp

### `expenses/{expenseId}`

- `description`: string
- `category`: string
- `amountMinor`: number
- `expenseDate`: timestamp
- `createdBy`: string
- `createdAt`: timestamp

### `settings/{settingId}`

Use a small number of known documents such as `settings/general` and `settings/pharmacy`.

- `pharmacyName`: string
- `phone`: string, optional
- `address`: string, optional
- `currency`: string
- `receiptFooter`: string, optional
- `updatedBy`: string
- `updatedAt`: timestamp

## Data rules

- Never trust totals, prices, roles, or stock quantities from the client without validating them in trusted server-side code or a controlled transaction.
- A sale should update `medicines.quantityOnHand` and create a `stock_movements` record atomically.
- A received purchase should update stock and create movement records atomically.
- Prefer voiding or refunding a sale over deleting it.
- Keep immutable audit information in `stock_movements`.
