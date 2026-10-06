package main

import (
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5"
)

// Staff management (owners only): who can use the panel and with which role. A new account
// gets a temporary password the owner reads to them; it must be changed at the first login,
// where the second factor is also enrolled.

func (a *API) adminStaffRoutes(api adminRouter) {
	api("GET /admin/api/staff", roleOwner, a.adminStaffList)
	api("POST /admin/api/staff", roleOwner, a.adminStaffCreate)
	api("POST /admin/api/staff/{id}/update", roleOwner, a.adminStaffUpdate)
	api("POST /admin/api/staff/{id}/reset-2fa", roleOwner, a.adminStaffReset2FA)
	api("POST /admin/api/staff/{id}/reset-password", roleOwner, a.adminStaffResetPassword)
}

func (a *API) adminStaffList(w http.ResponseWriter, r *http.Request, s *adminSession) {
	rows, err := a.store.jsonRows(r.Context(), `SELECT id, username, role, totp_enabled, active, must_change_password,
		(locked_until IS NOT NULL AND locked_until > now()) AS locked, created_by, created_at, last_login,
		(SELECT count(*) FROM admin_sessions s WHERE s.admin_id = u.id AND s.expires_at > now())::int AS sessions
		FROM admin_users u ORDER BY id`)
	a.adminReply(w, rows, err)
}

func (a *API) adminStaffCreate(w http.ResponseWriter, r *http.Request, s *adminSession) {
	var body struct {
		Username string `json:"username"`
		Role     string `json:"role"`
	}
	if err := readJSON(r, &body); err != nil || !usernamePattern.MatchString(body.Username) || roleRanks[body.Role] == 0 {
		a.badInput(w, "Usuário de 3 a 16 letras, números ou _ e um papel válido.")
		return
	}
	password, err := tempPassword()
	if err != nil {
		a.fail(w, err)
		return
	}
	hash, err := hashPassword(password, a.cfg.PBKDF2Iterations)
	if err != nil {
		a.fail(w, err)
		return
	}
	var id int64
	entry := adminEntry{Action: "staff.create", TargetType: "admin", TargetID: body.Username, Detail: map[string]any{"role": body.Role}}
	err = a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		err := tx.QueryRow(r.Context(), `INSERT INTO admin_users (username, password_hash, role, created_by, must_change_password) VALUES ($1, $2, $3, $4, true)
			ON CONFLICT DO NOTHING RETURNING id`, body.Username, hash, body.Role, s.Username).Scan(&id)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, preconditionError("Já existe alguém da equipe com este usuário.")
		}
		return map[string]any{"id": id}, err
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"id": id, "username": body.Username, "password": password})
}

func (a *API) adminStaffUpdate(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body struct {
		Role   *string `json:"role"`
		Active *bool   `json:"active"`
	}
	if err := readJSON(r, &body); err != nil || (body.Role == nil && body.Active == nil) || (body.Role != nil && roleRanks[*body.Role] == 0) {
		a.badInput(w, "Informe o papel e/ou a situação.")
		return
	}
	// Because nobody can change themselves, there is always at least one active owner: the
	// one making the change.
	if id == s.AdminID {
		writeError(w, http.StatusConflict, "conflict", "Você não pode mudar o seu próprio papel nem desativar a si mesmo.")
		return
	}
	entry := adminEntry{Action: "staff.update", TargetType: "admin", TargetID: idText(id), Detail: map[string]any{"role": body.Role, "active": body.Active}}
	err := a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		tag, err := tx.Exec(r.Context(), `UPDATE admin_users SET role = COALESCE($2, role), active = COALESCE($3, active) WHERE id = $1`, id, body.Role, body.Active)
		if err == nil && tag.RowsAffected() == 0 {
			err = ErrNotFound
		}
		if err != nil {
			return nil, err
		}
		// A change of role or a deactivation takes effect now, not at the next login.
		_, err = tx.Exec(r.Context(), `DELETE FROM admin_sessions WHERE admin_id = $1`, id)
		return nil, err
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// adminStaffReset2FA clears a lost second factor: the next login enrols a new one.
func (a *API) adminStaffReset2FA(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	entry := adminEntry{Action: "staff.reset_2fa", TargetType: "admin", TargetID: idText(id)}
	err := a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		tag, err := tx.Exec(r.Context(), `UPDATE admin_users SET totp_secret = '', totp_enabled = false, totp_last_step = 0 WHERE id = $1`, id)
		if err == nil && tag.RowsAffected() == 0 {
			err = ErrNotFound
		}
		if err != nil {
			return nil, err
		}
		_, err = tx.Exec(r.Context(), `DELETE FROM admin_sessions WHERE admin_id = $1`, id)
		return nil, err
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) adminStaffResetPassword(w http.ResponseWriter, r *http.Request, s *adminSession) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	password, err := tempPassword()
	if err != nil {
		a.fail(w, err)
		return
	}
	hash, err := hashPassword(password, a.cfg.PBKDF2Iterations)
	if err != nil {
		a.fail(w, err)
		return
	}
	entry := adminEntry{Action: "staff.reset_password", TargetType: "admin", TargetID: idText(id)}
	err = a.store.adminDo(r.Context(), s, entry, func(tx pgx.Tx) (map[string]any, error) {
		tag, err := tx.Exec(r.Context(), `UPDATE admin_users SET password_hash = $2, must_change_password = true, failed_logins = 0, locked_until = NULL WHERE id = $1`, id, hash)
		if err == nil && tag.RowsAffected() == 0 {
			err = ErrNotFound
		}
		if err != nil {
			return nil, err
		}
		_, err = tx.Exec(r.Context(), `DELETE FROM admin_sessions WHERE admin_id = $1`, id)
		return nil, err
	})
	if err != nil {
		a.adminFail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"password": password})
}
