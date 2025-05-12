## 🏗️ Step 1: Create a Multisig Account

```bash
aptos multisig create \
  --additional-owners 0x8... \
  --additional-owners 0x6... \
  --num-signatures-required 2 \
  --profile owner \
  --assume-yes
```

✅ Replace `0x8...` and `0x6...` with actual account addresses.  
✅ Save the returned **multisig address** in a variable like `$multisig_addr`.

---

## 📝 Step 2A: Create Transaction Using JSON File

**`transfer_payload.json` (Example content):**

```json
{
  "function_id": "0xc6::native_multisig::transfer_funds",
  "type_args": [],
  "args": [
    { "type": "address", "value": "0x82b..." },
    { "type": "u64", "value": "50" },
    { "type": "string", "value": "Test transfer from multisig" }
  ]
}
```

**Command:**

```bash
aptos multisig create-transaction \
  --multisig-address $multisig_addr \
  --json-file transfer_payload.json \
  --profile owner
```

---

## 🧾 Step 2B: Create Transaction Using CLI Arguments (No File)

```bash
aptos multisig create-transaction \
  --multisig-address $multisig_addr \
  --function-id 0xc6::native_multisig::transfer_funds \
  --args address:0x82b... u64:50 string:"Test transfer from multisig" \
  --profile owner
```

---

## 🔍 Step 3: View or Verify the Transaction

View the transaction by sequence number:

```bash
aptos move view \
  --function-id 0x1::multisig_account::get_transaction \
  --args address:"$multisig_addr" u64:1 \
  --profile owner
```

Check if the transaction can be executed:

```bash
aptos move view \
  --function-id 0x1::multisig_account::can_be_executed \
  --args address:"$multisig_addr" u64:2 \
  --profile admin
```

---

## ✅ Step 4: Approve and Execute the Transaction

Approve the transaction:

```bash
aptos multisig approve \
  --sequence-number 1 \
  --multisig-address $multisig_addr \
  --profile admin2 \
  --max-gas 20000 \
  --assume-yes
```

Execute the transaction:

```bash
aptos multisig execute \
  --multisig-address $multisig_addr \
  --profile owner
```
