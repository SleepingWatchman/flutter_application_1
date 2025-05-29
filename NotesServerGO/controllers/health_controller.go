package controllers

import (
	"encoding/json"
	"net/http"
)

// HealthCheck godoc
// @Summary Проверка состояния сервера
// @Description Возвращает статус "OK", если сервер работает
// @Tags Health
// @Produce json
// @Success 200 {object} map[string]string "Статус OK"
// @Router /health [get]
func HealthCheck(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "OK"})
}
