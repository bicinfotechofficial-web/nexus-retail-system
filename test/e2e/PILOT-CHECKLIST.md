# Pilot Checklist (QA-8)

A step-by-step script for the device pilot (task B-6) at one Caramel Cottage store. Work through it in order, with the store's two phones, the Bluetooth printer and a laptop for the admin console. Each step says **what to do**, **what you should see**, and **which sign-off item it proves** (the six acceptance items in `docs/01-MVP-SCOPE.md`, listed at the end).

Mark each step **Pass** or **Fail** in the box. When a step fails:
1. Stop. Don't repeat the step more than once.
2. Take a screenshot of the phone, and a photo of any receipt.
3. Write down the bill number, the phone (its device code, e.g. `D01`) and the time.
4. Carry on with the next section that doesn't depend on the failed one, and report the failure with those notes.

Words used here:
- **Phone A** and **Phone B**: the two store phones.
- **Store Manager login**: the email and password the Admin made for this store.
- **Offline**: the phone's airplane mode is on (Wi-Fi and mobile data off).
- **Sync chip**: the small label at the top right of the POS app: ● Online, ◐ Syncing, or ○ Offline since HH:MM.
- **Admin console**: the website the Admin signs in to on the laptop.

---

## 0. Before you start

- [ ] Two Android phones (Android 12 or newer), charged, with **date and time set to automatic**. Do not change the phone clock during the pilot (see the note in step 13).
- [ ] The POS app file (`.apk`) for this build, copied to both phones.
- [ ] The Bluetooth receipt printer, charged, with at least two paper rolls.
- [ ] A laptop with Chrome and internet, for the admin console.
- [ ] The Admin login and the Store Manager login for this store.
- [ ] The store's **override PIN** (8 digits or more). Only the Admin should type it.
- [ ] This checklist printed, a pen, a calculator, and an envelope to keep every receipt printed during the pilot.
- [ ] In the admin console, the store's details are filled in: name, address, phone, offline limit (5 hours), override PIN, and the receipt footer.
- [ ] At least five cakes or items are active with prices, and their stock has been entered.

---

## 1. Install the app
**Proves:** setup for everything below.

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 1.1 | On Phone A, open the `.apk` file and install it (allow "install unknown apps" if Android asks). | The app installs and opens to the sign-in screen. | |
| 1.2 | Do the same on Phone B. | The same. | |

## 2. Sign in and register each phone
**Proves:** #1 (every phone gets its own device code, so bill numbers never clash).

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 2.1 | With internet on, sign in on Phone A with the Store Manager login. | The app asks to set up this device. | |
| 2.2 | Give it a name such as "Counter 1" and register it. | A device code such as `D01`. Write it here: `______` | |
| 2.3 | Do the same on Phone B ("Counter 2"). | A **different** device code, such as `D02`. Write it here: `______` | |
| 2.4 | On the laptop, sign in to the admin console as the Admin and open **Devices** for this store. | Both phones are listed with their names and codes, and a "last seen" time from the last few minutes. | |
| 2.5 | On Phone A, turn internet off and try to register again (only if the app offers a "register again" option; otherwise skip). | The app says registration needs an internet connection. Turn internet back on. | |

## 3. Pair the printer and print a test
**Proves:** #4 (receipts can be printed at all).

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 3.1 | Turn the printer on. In Android Bluetooth settings on Phone A, pair with it (the PIN is usually `0000` or `1234`, see the printer's manual). | The printer shows as paired. | |
| 3.2 | In the POS app on Phone A, choose the printer and the paper width (80 mm unless the Admin said otherwise), then print a test page. | A test slip prints, with the ₹ sign or "Rs." printed clearly and nothing cut off at the edges. | |
| 3.3 | Repeat 3.1 and 3.2 on Phone B with the same printer (turn Phone A's Bluetooth off first if the printer only takes one connection). | The same. | |

## 4. Bill online and check the receipts
**Proves:** #4 (the printed receipt matches the saved bill).

Keep every receipt in the envelope; you'll need them in step 14.

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 4.1 | On Phone A, with internet on, add two items to the cart and charge it. Pay the full amount in **Cash**, enter a larger amount as "cash tendered" (e.g. ₹500 for a ₹360 bill), and save. | "Bill saved" with a bill number like `PTB-D01-000001`, the change to return, and a receipt prints. | |
| 4.2 | Check the receipt from 4.1 line by line against the screen. | The receipt shows: store name, address and phone; the bill number; date and time; each item with qty, price and line total; subtotal; discount (none); **round-off**; total; payment Cash with the amount, cash tendered and change; "served by" with the Store Manager's name; and the footer. Every amount matches the screen. | |
| 4.3 | New bill on Phone A with three items. Give a **% discount** (e.g. 10%) and split the payment: part UPI, part Card, the rest Cash. | Save is only possible when the payments add up exactly to the total. The receipt shows the discount line, the round-off line (for example −₹0.40 or +₹0.30), and each payment on its own line. | |
| 4.4 | Try a discount above the store's limit (only if the Admin set one), e.g. 50%. | The app refuses it with a message about the store's limit, and nothing is saved. | |
| 4.5 | Try to save with payments that don't add up to the total. | The Save button stays off and the screen shows how much is remaining or over. | |
| 4.6 | Tap Save twice very quickly on a new bill. | Only **one** bill is saved (check the Bills list: one new bill number, not two). | |
| 4.7 | Open the Bills list, pick the bill from 4.1 and reprint it. | The reprint matches the first receipt and has a "REPRINT" line. | |

## 5. Check the saved bill on the admin console
**Proves:** #4 (the receipt matches the bill as saved on the server) and #5.

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 5.1 | On the admin console, open today's dashboard for this store. | Bills = 3 (or however many you saved), and the "Sales" total equals the sum of the receipt totals so far. | |

## 6. Go offline and bill on both phones
**Proves:** #1 (two phones bill offline at the same time, with no duplicate bill numbers).

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 6.1 | Pick one item that both phones will sell (call it **Item X**). In the stock screen, write down its quantity: `______` | | |
| 6.2 | Turn on airplane mode on **both** phones. | The sync chip shows "○ Offline since" and the time. | |
| 6.3 | On Phone A make 5 bills, and on Phone B make 5 bills, at the same time if you can. Both phones must sell **Item X** at least twice. Use a mix of cash and UPI. | Every bill saves and prints straight away, even offline. Phone A's bill numbers carry its code (`…-D01-…`) and Phone B's carry its own; the numbers on each phone go up by one each time. | |
| 6.4 | Write down how many of Item X were sold in total on both phones: `______` | | |

## 7. Close the app and restart the phone mid-way
**Proves:** #2 (closing the app or restarting the phone never makes a duplicate bill or takes stock twice).

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 7.1 | Still offline, on Phone A start a new bill and tap Save. As soon as "Bill saved" appears, swipe the app away from the recent-apps screen. | | |
| 7.2 | Open the app again. Open the Bills list for today. | The bill from 7.1 is there **once**. If it didn't print, reprint it now. | |
| 7.3 | Still offline, restart Phone A (power off and on). Open the app. | You're still signed in. All of today's offline bills are in the Bills list, each once. | |

## 8. Sync and check
**Proves:** #1 (exact stock and no duplicates after sync) and #2.

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 8.1 | Turn airplane mode off on both phones. | The sync chip shows "◐ Syncing" with a count, then "● Online" within a couple of minutes. | |
| 8.2 | Open the sync-health screen on each phone. | **No sync errors.** | |
| 8.3 | Check Item X's stock on either phone. | Its quantity is the number from 6.1 minus the total from 6.4 (and minus any sold in step 7). It may be negative; that's allowed and shows in red. | |
| 8.4 | On the admin console, look at today's bill count. | It equals every bill printed so far, with no bill number appearing twice. | |
| 8.5 | On the admin console, open Devices. | Both phones show a recent "last seen" time. | |

## 9. Cancel a bill
**Proves:** #5 (cancellations are reflected in the totals) and the same-day cancel rule.

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 9.1 | Write down Item X's stock: `______`. On Phone A, open one of **today's** bills that has Item X, cancel it and type a reason ("customer changed order"). | The bill shows as CANCELLED. Reprinting it shows a CANCELLED banner with the reason. Mark the paper receipt "CANCELLED" and keep it. | |
| 9.2 | Check Item X's stock. | It went back up by the qty on the cancelled bill. | |
| 9.3 | Try to cancel the same bill again. | Not possible; it's already cancelled. | |
| 9.4 | (Next day only.) Try to cancel a bill from the day before. | The app refuses: only same-day bills can be cancelled; it offers a return instead. | |

## 10. Return part of a bill
**Proves:** #4 (return slips) and #5 (returns are reflected in the totals).

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 10.1 | On Phone B, find a bill with at least 2 of one item. Return **1** of it, refunding part in Cash and part in UPI. | A return slip prints with the original bill number, the returned item and qty, the refund total and each refund mode. Keep it. | |
| 10.2 | Check that item's stock. | Up by 1. | |
| 10.3 | Try to return more of that item than is left on the bill. | The app doesn't allow a quantity above what's left. | |
| 10.4 | Try to cancel the bill from 10.1. | The app refuses: a bill with a return can't be cancelled. | |
| 10.5 | Try to start a return on the bill you cancelled in 9.1. | The app refuses: a cancelled bill can't be returned. | |

## 11. (Optional) Two phones act on the same bill offline
**Proves:** that clashes are caught, not doubled. Do this only if steps 1–10 passed.

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 11.1 | With internet on, make a new bill with 2 items on Phone A. Wait until both phones show ● Online. Turn airplane mode on for both. | | |
| 11.2 | On Phone A, return 1 item of that bill. On Phone B, cancel the same bill. | Both phones allow it (they can't see each other). | |
| 11.3 | Turn internet on for **Phone A first**, wait for ● Online, then Phone B. | Phone A has no sync errors. Phone B's sync-health screen shows **one sync error** for the cancel. On the admin console, the bill is not cancelled and its return counts once. Tell the customer only the return stands. | |

## 12. Stock operations
**Proves:** stock is recorded correctly (part of #1's "stock that is exactly correct").

For each row, write the item's quantity before and after.

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 12.1 | **Stock In**: receive a raw material, e.g. 5000 g of cake mix, with a note naming the supplier. | Its stock goes up by 5000 g. | |
| 12.2 | **Stock Out**: take out 200 g of a raw material with a reason. | Down by 200 g. | |
| 12.3 | **Wastage (raw)**: 100 ml of cream, reason "spoiled". | Down by 100 ml. | |
| 12.4 | **Produce**: use 1000 g cake mix and 500 ml cream to make 2 of a cake. | Cake mix down 1000 g, cream down 500 ml, the cake up by 2, all in one step. | |
| 12.5 | **Wastage (finished)**: 1 cake, reason "dropped". | Down by 1. | |
| 12.6 | **Adjust**: count an item on the shelf (with internet on) and enter the real count. | The stock now shows exactly your count. | |
| 12.7 | Set a **low-stock level** for one item just above its current quantity. | The low-stock badge and list show that item. The admin console's low-stock list shows it too. | |
| 12.8 | Sell an item until its stock is below zero. | The sale is never blocked, and the negative quantity shows in red. | |
| 12.9 | **Suggest a local special** with a proposed price. | It does **not** appear in the billing screen. After the Admin approves it on the console with a price, it appears and can be billed. | |
| 12.10 | On the admin console, open the Audit log for this store. | The wastage entries and the adjust entry are listed, with who did them and when. | |

## 13. Offline limit and the override PIN
**Proves:** #6 (at the offline limit billing is blocked, and an Admin PIN allows billing for the next 2 hours).

The normal limit is 5 hours. To avoid a 5-hour wait, the Admin sets it to **1 hour** for this test and puts it back after.

Note: the offline timer follows the phone's clock. Changing the phone's clock would get around it; that's a known pilot limitation, so don't do it.

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 13.1 | Admin: on the console, set this store's offline limit to 1 hour. On Phone A, with internet on, wait until ● Online (so the phone has the new limit). Note the time: `______` | | |
| 13.2 | Turn on airplane mode on Phone A. Keep billing now and then. | At about **48 minutes** offline, an amber banner says billing will stop soon, with the minutes left. Billing still works. | |
| 13.3 | At **60 minutes** offline, try to make a bill. | Billing is blocked, with a screen offering "Retry sync" and "Admin PIN override". | |
| 13.4 | While blocked, open the stock screen and do a Stock In; open the Bills list and reprint a bill. | Both still work. Only new bills are blocked. | |
| 13.5 | Swipe the app away and open it again (still offline). | Still blocked. (If it lets you bill, that's a **Fail**; write it down.) | |
| 13.6 | Enter a **wrong** PIN. | Refused; still blocked. | |
| 13.7 | The Admin enters the **correct** PIN. Note the time: `______` | Billing works again. Make one bill. | |
| 13.8 | (If you can wait.) Stay offline until 2 hours after 13.7. | Billing is blocked again at 2 hours after the PIN was entered. | |
| 13.9 | Turn internet on. Wait for ● Online. | Billing works without a PIN. On the admin console's Audit log, an "offline override" entry for Phone A is listed at the time of 13.7. | |
| 13.10 | Admin: set the offline limit back to **5 hours**. | | |

## 14. Check today's totals on the admin console against the receipts
**Proves:** #5 (the admin's daily totals equal the sum of the bills and returns for that day).

Spread out every receipt and slip from today. Fill in this sheet, then compare it with the admin console (today, this store).

| Line | How to work it out from the paper | Your figure | Admin console | Match? |
|---|---|---|---|---|
| Bills | Count every bill receipt (not reprints), **including** cancelled ones | | "Bills" | |
| Billed total | Add up the total of every bill receipt, including cancelled ones | | "Net sales" or the as-billed line | |
| Cancellations | Add up the totals of the receipts marked CANCELLED | | "Cancellations" | |
| Returns | Add up the refund totals on the return slips | | "Returns" | |
| **Sales (net revenue)** | Billed total − Cancellations − Returns | | The headline "Sales" / "Net revenue" | |
| Cash | Cash payments on bills that are not cancelled − cash refunds | | By payment mode: Cash | |
| UPI | The same for UPI | | UPI | |
| Card | The same for Card | | Card | |
| Wallet and Other | The same for each | | Wallet, Other | |

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 14.1 | Compare every line of the sheet with the console. | Every figure matches to the paisa. | |
| 14.2 | Check that the headline figure on the dashboard is the Sales (net revenue) line, not the billed total. | The headline is Sales = billed − cancellations − returns. (Known issue QA-028: until it's fixed, the dashboard shows "Net sales" first; note which figure it shows.) | |
| 14.3 | Open the monthly report for this month. | Today's figures are included, and the month equals the sum of its days so far. | |

## 15. Store Managers see only their own store
**Proves:** #3 (a Store Manager cannot read or write another location's data). The real proof is the security-rules tests run by the developers; this is the check a user can see.

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 15.1 | Sign in to the admin console with the **Store Manager** login. | Only this store appears in the location picker, with no "All locations" option. There is no Users, Locations or Expenses page. | |
| 15.2 | (Only if a second store exists.) Look for the other store's name anywhere. | It's not shown anywhere. | |
| 15.3 | Sign out, and sign back in as the Admin. | "All locations" is available again. | |

## 16. (Optional) A disabled login while offline
**Proves:** a disabled login can't add bills later. Needs a spare Store Manager login made for the test.

| # | Do | You should see | Pass / Fail |
|---|---|---|---|
| 16.1 | Sign in on Phone B with the spare login, go offline and make one bill. | The bill saves and prints. Mark that receipt "TEST, DISABLED". | |
| 16.2 | On the admin console, disable the spare login. Then turn Phone B's internet on. | Phone B's sync-health screen shows a sync error for that bill, and it isn't in the console's totals. Leave that receipt out of step 14. | |
| 16.3 | Try to sign in with the spare login. | Refused: the login has been disabled. | |

---

## Sign-off

| Acceptance item (01-MVP-SCOPE) | Steps | Pass / Fail |
|---|---|---|
| 1. Two devices bill offline at the same time, then sync, with no duplicate bill numbers and exactly correct stock | 2, 6, 8, 12 | |
| 2. Closing the app or restarting the phone mid-bill never makes a duplicate bill or a double stock deduction | 4.6, 7, 8 | |
| 3. A Store Manager can't read or write another location's data | 15 (plus the developers' rules tests) | |
| 4. A printed receipt matches the saved bill in every printed field | 3, 4, 5, 9.1, 10.1 | |
| 5. The admin's daily totals equal the bills and returns of the day | 5, 9, 10, 14 | |
| 6. At the offline limit billing is blocked, and an Admin PIN allows billing for the next 2 hours | 13 | |

Pilot date: `__________`  Store: `__________`  Checked by: `__________`
