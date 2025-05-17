using SQLite;
using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;
using System;

namespace NotesServer.Models
{
    public class ScheduleEntry : DatabaseEntity
    {
        [PrimaryKey, AutoIncrement]
        [JsonPropertyName("id")]
        public int Id { get; set; }
        [Required]
        [JsonPropertyName("time")]
        public string Time { get; set; } = string.Empty;
        [Required]
        [JsonPropertyName("date")]
        public string Date { get; set; } = string.Empty;
        [JsonPropertyName("note")]
        public string? Note { get; set; }
        [JsonPropertyName("dynamicFieldsJson")]
        public string? DynamicFieldsJson { get; set; }
        [JsonPropertyName("createdAt")]
        public DateTime CreatedAt { get; set; }
    }
} 