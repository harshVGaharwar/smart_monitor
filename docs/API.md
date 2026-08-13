# Smart Monitor — API

**Base URL:** `http://localhost:8080/api`



---

## 1. POST `/login`

**Request**
```json
{
  "Id": 0,
  "Name": "maker",
  "EmployeeCode": "n2346",
  "Email": "",
  "password": "test123",
  "Location": "",
  "LOCATIONCODE": "",
  "City": "",
  "Department": "",
  "ContactNumber": "",
  "Role": "",
  "IPAddress": "",
  "ProfileDescription": "",
  "ProfileId": ""
}
```

**Response** (not wrapped)
```json
{
  "token": "local-1786597764694",
  "refreshToken": "local-refresh",
  "user": {
    "id": 1,
    "name": "Maker",
    "employeeCode": "OFF807292",
    "email": "maker@example.internal",
    "location": "Mumbai",
    "locationCode": "MUM",
    "city": "Mumbai",
    "contactNumber": "",
    "role": "Maker",
    "profileDescription": "Maker",
    "profileId": "P1",
    "menuList": [
      { "id": 1, "menuName": "Dashboard", "profileId": "P1", "isActive": "Y" },
      { "id": 2, "menuName": "MIS", "profileId": "P1", "isActive": "N" },
      { "id": 3, "menuName": "Upload Document", "profileId": "P1", "isActive": "Y" }
    ]
  }
}
```

**Error 401**
```json
{ "message": "That username and password did not match." }
```

Test accounts (any password): `maker` / `checker`

---

## 2. GET `/get-smartpointer`

**Request**
```
/api/get-smartpointer?employeeCode=OFF807292&role=Maker
```

| Param | Value |
|---|---|
| `employeeCode` | `OFF807292` (Maker) / `r14878` (Checker) |
| `role` | `Maker` / `Checker` |

**Response**
```json
{
  "code": 0,
  "message": "Upload Successful",
  "body": null,
  "success": true,
  "data": {
    "rows": [
      {
        "client_id": "2287410",
        "customer_name": "NORTHGATE LOGISTICS LIMITED",
        "account_no": "11930442",
        "line_no": "50301271033039",
        "health_check_category": "Insurance Expiry Health Check",
        "sub_category": "Policy lapsed",
        "support_system": "LMM",
        "core_system": "FC",
        "exception_category": "Exception",
        "reason": "Insurance Policy Expired; Renewed Copy To Be Obtained",
        "cpu": "Kolkata",
        "team": "Insurance Team",
        "segment": "Corporate",
        "facility": "Term Loan",
        "sr_no": 3,
        "maker": "OFF807292",
        "checker": "r14878",
        "ls_srm_date": "2026-05-29",
        "assigned_by": null,
        "assigned_date": "0001-01-01",
        "priority": null,
        "message_count": 0,
        "last_message": null,
        "status": "Pending with Health Checker",
        "imported_at": "2026-08-13T05:18:00.142363Z"
      }
    ]
  },
  "count": 0,
  "userName": null, "userCode": null,
  "branchName": null, "branchCode": null, "menu": null
}
```



## 3. POST `/read-excel`

**Request** — `multipart/form-data`

| Field | Type | Value |
|---|---|---|
| `file` | File | `cases.xlsx` (max 25 MB, `.xlsx` or `.csv`) |
| `fileType` | Text | `xlsx` |

**Response** — same row shape as `/get-smartpointer`, without `status` and `imported_at`
```json
{
  "code": 0,
  "message": "Upload Successful",
  "success": true,
  "data": { "rows": [ { "client_id": "2287410", "customer_name": "...", "sr_no": 3, "...": "..." } ] },
  "count": 0
}
```



## 4. POST `/update-smartpointer`

**Request** — all values are strings
```json
{
  "rows": [
    {
      "client_id": "2287410",
      "customer_name": "NORTHGATE LOGISTICS LIMITED",
      "account_no": "11930442",
      "line_no": "50301271033039",
      "health_check_category": "Insurance Expiry Health Check",
      "sub_category": "Policy lapsed",
      "support_system": "LMM",
      "core_system": "FC",
      "exception_category": "Exception",
      "reason": "Insurance Policy Expired; Renewed Copy To Be Obtained",
      "cpu": "Kolkata",
      "team": "Insurance Team",
      "segment": "Corporate",
      "facility": "Term Loan",
      "sr_no": "3",
      "maker": "OFF807292",
      "checker": "r14878",
      "ls_srm_date": "2026-05-29",
      "status": "Pending with CPU"
    }
  ]
}
```

**Response**
```json
{
  "code": 0,
  "message": "Updated Successfully",
  "success": true,
  "data": {
    "rows": [ { "client_id": "2287410", "...": "..." } ],
    "inserted": 1,
    "updated": 0,
    "total": 1
  },
  "count": 1
}
```


## 5. POST `/verify`

**Request** — Maker
```json
{
  "clientId": "2287410",
  "userId": "OFF807292",
  "role": "Maker",
  "comments": "Lien released, checked in core.",
  "isVerified": "yes",
  "status": null
}
```

**Request** — Checker
```json
{
  "clientId": "2287410",
  "userId": "r14878",
  "role": "Checker",
  "comments": "Looks fine, approving.",
  "isVerified": null,
  "status": "Approved"
}
```

With a file — `multipart/form-data`, same fields as Text + `supportDocument` as File. Null values go as the text `null`.

| Field | Who | Values |
|---|---|---|
| `isVerified` | Maker only | `yes` / `no` / `null` |
| `status` | Checker only | `Approved` / `Reject` / `null` |

Yes = `yes` / `y` / `true` / `1` (any casing). Anything else = no.

**Accepted aliases** — server reads both spellings, client sends the first:

| Sent | Also accepted |
|---|---|
| `clientId` | `clientID` |
| `userId` | `userID` |
| `comments` | `verificationComment` |
| `isVerified` | `isVerify` |
| `status: "Approved"` | `isApproved: "yes"` |

`isApproved` can only approve — there is no reject equivalent, so use `status`
when you need `Reject`.

**Response** — `data` is the number of rows moved
```json
{ "code": 0, "message": "Updated Successfully", "success": true, "data": 1, "count": 1 }
```

## 6. POST `/reassign`

Maker only.

**Request**
```json
{
  "clientId": "2287410",
  "userId": "OFF807292",
  "role": "Maker",
  "cpu": "Chennai",
  "team": "Disbursement Team",
  "reason": "Incorrect CPU mapping",
  "comments": "Wrong team, sending this back.",
  "document": null
}
```

With a file — `multipart/form-data`, same fields as Text + `document` as File.

`clientID` / `userID` also accepted.

**Response**
```json
{ "code": 0, "message": "Successfully assigned to new user", "success": true, "data": 1, "count": 1 }
```


---

## 7. GET `/getComments`

**Request**
```
/api/getComments?clientId=2287410&userId=r14878
```

**Response**
```json
{
  "code": 0,
  "message": "Comments Loaded",
  "success": true,
  "data": {
    "comments": [
      {
        "clientId": "2287410",
        "userId": "r14878",
        "role": "Checker",
        "comments": "Checked in core, lien released.",
        "supportDocument": "policy-renewal.pdf",
        "reason": "",
        "createdAt": "2026-08-13T05:22:11.004Z"
      }
    ]
  },
  "count": 0
}
```


## 8. POST `/addComment`

**Request**
```json
{
  "clientId": "2287410",
  "userId": "r14878",
  "comments": "Checked in core, lien released.",
  "role": "Checker"
}
```

File ke saath — `multipart/form-data`, wahi 4 fields Text me + `supportDocument` as File.

**Response**
```json
{
  "code": 0,
  "message": "Comment Added",
  "success": true,
  "data": {
    "comment": {
      "clientId": "2287410",
      "userId": "r14878",
      "role": "Checker",
      "comments": "Checked in core, lien released.",
      "supportDocument": "",
      "reason": "",
      "createdAt": "2026-08-13T06:27:26.938542Z"
    }
  },
  "count": 0
}
```


## 9. GET `/getDocuments`

**Request** — note the capital `ID` in `userID` (lowercase `userId` also accepted)
```
/api/getDocuments?clientId=2287410&userID=r14878
```

**Response**
```json
{
  "code": 0,
  "message": "Documents Loaded",
  "success": true,
  "data": {
    "documents": [
      {
        "clientId": "2287410",
        "userID": "OFF807292",
        "fileName": "policy-renewal.pdf",
        "uploadedBy": "Maker",
        "uploadedDate": "2026-08-13T05:22:11.004Z"
      }
    ]
  },
  "count": 0
}
```


## 10. GET `/getMasterData`

Dropdowns aur upload validation ki reference lists. Koi parameter nahi — sabke liye same.

**Request**
```
/api/getMasterData
```

**Response**
```json
{
  "code": 0,
  "message": "Master Data Loaded",
  "body": null,
  "success": true,
  "data": {
    "cpus": ["Ahmedabad", "Chennai", "Gurgaon", "Kolkata", "Mohali", "Mumbai"],
    "teams": [
      "Agri Foreclosure Team", "Cam Renewal Team", "Cam Updation Team",
      "Centralized Mis Team", "Disbursement Team", "Foreclosure Team",
      "Gift City Team", "Guarantee Team", "Insurance Team",
      "Inventory funding team", "LAD Team", "LMS Team",
      "Pmt- Property Management", "Retail Lc- Bg Team", "StaffLoan Team",
      "Stock Statement Team", "Trade/ Limit Setting Team"
    ],
    "exceptionCategories": ["Exception", "Exclusion"],
    "healthCheckCategories": [
      "CAM Expiry Health Check", "LMM vs UBS Mismatch", "FD Exceptions",
      "Stock Statement Health Check", "Insurance Expiry Health Check",
      "Legal Document Health Check"
    ],
    "jabreassignReasons": [
      "Incorrect CPU mapping", "Incorrect team mapping", "Workload rebalancing",
      "Requires specialist review", "Raised in error"
    ]
  },
  "count": 0,
  "userName": null, "userCode": null,
  "branchName": null, "branchCode": null, "menu": null
}
```
