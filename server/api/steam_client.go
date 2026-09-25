package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// SteamClient talks to the Steam Web API with the publisher key (partner.steam-api.com):
// ISteamUserAuth/AuthenticateUserTicket (login with the ticket from
// GetAuthTicketForWebApi) and ISteamMicroTxn (purchases with the Steam Wallet; the
// sandbox interface while testing). Tests point Base at a fake server.
type SteamClient struct {
	Base     string
	Key      string
	AppID    uint32
	Identity string
	Sandbox  bool
	HTTP     *http.Client
}

// SteamError is an error answered by Steam (errorcode and errordesc).
type SteamError struct {
	Code int
	Desc string
}

func (e *SteamError) Error() string { return fmt.Sprintf("steam error %d: %s", e.Code, e.Desc) }

var ErrSteamDisabled = errors.New("steam is not configured")

// SteamUser is who a login ticket belongs to.
type SteamUser struct {
	SteamID         string
	OwnerSteamID    string
	PublisherBanned bool
	VACBanned       bool
}

func (c *SteamClient) Enabled() bool {
	return c != nil && c.Key != "" && c.AppID != 0
}

func (c *SteamClient) client() *http.Client {
	if c.HTTP != nil {
		return c.HTTP
	}
	return &http.Client{Timeout: 15 * time.Second}
}

func (c *SteamClient) call(ctx context.Context, method, path string, params url.Values) (map[string]any, error) {
	if !c.Enabled() {
		return nil, ErrSteamDisabled
	}
	params.Set("key", c.Key)
	params.Set("appid", strconv.FormatUint(uint64(c.AppID), 10))
	endpoint := strings.TrimSuffix(c.Base, "/") + path
	var request *http.Request
	var err error
	if method == http.MethodGet {
		request, err = http.NewRequestWithContext(ctx, method, endpoint+"?"+params.Encode(), nil)
	} else {
		request, err = http.NewRequestWithContext(ctx, method, endpoint, strings.NewReader(params.Encode()))
		if request != nil {
			request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		}
	}
	if err != nil {
		return nil, err
	}
	reply, err := c.client().Do(request)
	if err != nil {
		return nil, err
	}
	defer reply.Body.Close()
	var body struct {
		Response map[string]any `json:"response"`
	}
	if err := json.NewDecoder(reply.Body).Decode(&body); err != nil {
		return nil, fmt.Errorf("steam %s: HTTP %d: %w", path, reply.StatusCode, err)
	}
	if body.Response == nil {
		return nil, fmt.Errorf("steam %s: HTTP %d without a response", path, reply.StatusCode)
	}
	return body.Response, nil
}

func steamErr(response map[string]any) error {
	if raw, ok := response["error"].(map[string]any); ok {
		code, _ := raw["errorcode"].(float64)
		desc, _ := raw["errordesc"].(string)
		return &SteamError{Code: int(code), Desc: desc}
	}
	return nil
}

// AuthenticateTicket checks a ticket from the game (hex of GetAuthTicketForWebApi, made
// for c.Identity) and says whose it is.
func (c *SteamClient) AuthenticateTicket(ctx context.Context, ticket string) (SteamUser, error) {
	params := url.Values{"ticket": {ticket}}
	if c.Identity != "" {
		params.Set("identity", c.Identity)
	}
	response, err := c.call(ctx, http.MethodGet, "/ISteamUserAuth/AuthenticateUserTicket/v1/", params)
	if err != nil {
		return SteamUser{}, err
	}
	if err := steamErr(response); err != nil {
		return SteamUser{}, err
	}
	result, _ := response["params"].(map[string]any)
	if result == nil || result["result"] != "OK" {
		return SteamUser{}, &SteamError{Desc: fmt.Sprint(response)}
	}
	user := SteamUser{SteamID: fmt.Sprint(result["steamid"]), OwnerSteamID: fmt.Sprint(result["ownersteamid"])}
	user.PublisherBanned, _ = result["publisherbanned"].(bool)
	user.VACBanned, _ = result["vacbanned"].(bool)
	return user, nil
}

func (c *SteamClient) microTxn(ctx context.Context, method, name string, params url.Values) (map[string]any, error) {
	iface := "ISteamMicroTxn"
	if c.Sandbox {
		iface = "ISteamMicroTxnSandbox"
	}
	response, err := c.call(ctx, method, "/"+iface+"/"+name+"/", params)
	if err != nil {
		return nil, err
	}
	if err := steamErr(response); err != nil {
		return nil, err
	}
	if response["result"] != "OK" {
		return nil, &SteamError{Desc: fmt.Sprint(response)}
	}
	result, _ := response["params"].(map[string]any)
	if result == nil {
		result = map[string]any{}
	}
	return result, nil
}

// UserInfo gives the currency of the player's Steam Wallet (the price must be in it).
func (c *SteamClient) UserInfo(ctx context.Context, steamID string) (currency, country string, err error) {
	result, err := c.microTxn(ctx, http.MethodGet, "GetUserInfo/v2", url.Values{"steamid": {steamID}})
	if err != nil {
		return "", "", err
	}
	currency, _ = result["currency"].(string)
	country, _ = result["country"].(string)
	return currency, country, nil
}

// InitTxn opens the purchase: the Steam overlay asks the player to approve it.
func (c *SteamClient) InitTxn(ctx context.Context, order Order, language string) error {
	params := url.Values{
		"orderid":        {strconv.FormatInt(order.OrderID, 10)},
		"steamid":        {order.SteamID},
		"itemcount":      {"1"},
		"language":       {language},
		"currency":       {order.Currency},
		"usersession":    {"client"},
		"itemid[0]":      {strconv.FormatInt(order.SteamItemID, 10)},
		"qty[0]":         {"1"},
		"amount[0]":      {strconv.Itoa(order.Amount)},
		"description[0]": {truncate(order.Description, 128)},
		"category[0]":    {"cosmetic"},
	}
	_, err := c.microTxn(ctx, http.MethodPost, "InitTxn/v3", params)
	return err
}

// FinalizeTxn charges the order the player approved.
func (c *SteamClient) FinalizeTxn(ctx context.Context, orderID int64) error {
	_, err := c.microTxn(ctx, http.MethodPost, "FinalizeTxn/v2", url.Values{"orderid": {strconv.FormatInt(orderID, 10)}})
	return err
}

// QueryTxn says where an order stands on Steam: Init, Approved, Succeeded, Failed,
// Refunded, PartialRefund, Chargedback...
func (c *SteamClient) QueryTxn(ctx context.Context, orderID int64) (string, error) {
	result, err := c.microTxn(ctx, http.MethodGet, "QueryTxn/v3", url.Values{"orderid": {strconv.FormatInt(orderID, 10)}})
	if err != nil {
		return "", err
	}
	status, _ := result["status"].(string)
	return status, nil
}
