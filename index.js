const axios = require("axios");

const url = "https://api.story.faucetme.pro/wallet/request-token";
const payload = {
  address: "0x28f9d26a2089aa42b11CA8a9ACaB14b9922Ec231",
  denom: "IP",
  rolesId: [],
  userId: "1268237438560764026",
};

const headers = {
  "Content-Type": "application/json",
  Authorization: "Bearer 196595|2xaMS9Ih5gi7f2VQGxqrEgF7jBHhVd",
  Accept: "*/*",
  "Accept-Encoding": "gzip, deflate, br, zstd",
  "Accept-Language": "vi,en-US;q=0.9,en;q=0.8",
  Origin: "https://story.faucetme.pro",
  Referer: "https://story.faucetme.pro/",
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36 Edg/128.0.0.0",
};

axios
  .post(url, payload, { headers: headers })
  .then((response) => console.log(response.data))
  .catch((error) => console.error("Error:", error));
