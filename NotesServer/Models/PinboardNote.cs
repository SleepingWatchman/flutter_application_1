using System;
using SQLite;
using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace NotesServer.Models
{
    public class PinboardNote : DatabaseEntity
    {
        [PrimaryKey, AutoIncrement]
        [JsonPropertyName("id")]
        public int Id { get; set; }

        [Required]
        [JsonPropertyName("title")]
        public string Title { get; set; } = string.Empty;

        [Required]
        [JsonPropertyName("content")]
        public string Content { get; set; } = string.Empty;

        [JsonPropertyName("positionX")]
        public double PositionX { get; set; }

        [JsonPropertyName("positionY")]
        public double PositionY { get; set; }

        [JsonPropertyName("width")]
        public double Width { get; set; }

        [JsonPropertyName("height")]
        public double Height { get; set; }

        [JsonPropertyName("backgroundColor")]
        public int BackgroundColor { get; set; }

        [JsonPropertyName("icon")]
        public int Icon { get; set; }
    }
} 