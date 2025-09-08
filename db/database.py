import sqlite3
import os

DB_PATH = 'db/user_data.db'

def init_db():
    os.makedirs('db', exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''CREATE TABLE IF NOT EXISTS counters
    (user_id INTEGER, time_name TEXT, number INTEGER)''')
    

    conn.execute('''CREATE TABLE IF NOT EXISTS favorites
    (user_id INTEGER, 
     book_name TEXT,
     book_author TEXT,
     book_description TEXT,
     is_read INTEGER DEFAULT 0,
     added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)''')
     
    
    conn.execute('''CREATE TABLE IF NOT EXISTS user_stats
    (user_id INTEGER PRIMARY KEY,
     first_interaction_date TEXT)''')
    
    conn.close()

def get_number(user_id, time_name):
    conn = sqlite3.connect(DB_PATH)
    result = conn.execute('''SELECT number FROM counters WHERE user_id=? AND time_name=?''',
    (user_id, time_name)).fetchone()
    conn.close()
    if result:
        return result[0]
    else:
        return 0


def save_number(user_id, time_name, number):
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''DELETE FROM counters WHERE user_id=? AND time_name=?''', (user_id, time_name))
    conn.execute('''INSERT INTO counters VALUES (?, ?, ?)''', (user_id, time_name, number))
    conn.commit()
    conn.close()


def get_total_booksdb(user_id):
    conn = sqlite3.connect(DB_PATH)
    result = conn.execute('''SELECT number FROM counters WHERE user_id=? AND time_name=?''',
    (user_id, 'total_books')).fetchone()
    conn.close()
    if result:
        return result[0]
    else:
        return 0

def increment_total_books(user_id):
    current_total = get_total_booksdb(user_id)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''DELETE FROM counters WHERE user_id=? AND time_name=?''', (user_id, 'total_books'))
    conn.execute('''INSERT INTO counters VALUES (?, ?, ?)''', (user_id, 'total_books', current_total + 1))
    conn.commit()
    conn.close()

def add_to_favorites(user_id, book_name, book_author, book_description):
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''INSERT INTO favorites (user_id, book_name, book_author, book_description)
                    VALUES (?, ?, ?, ?)''', 
                    (user_id, book_name, book_author, book_description))
    conn.commit()
    conn.close()

def is_in_favorites(user_id, book_name, book_author):
    conn = sqlite3.connect(DB_PATH)
    result = conn.execute('''SELECT 1 FROM favorites 
                            WHERE user_id=? AND book_name=? AND book_author=?''',
                            (user_id, book_name, book_author)).fetchone()
    conn.close()
    return bool(result)

def get_favorites(user_id, is_read=None):
    conn = sqlite3.connect(DB_PATH)
    if is_read is None:
        favorites = conn.execute('''SELECT book_name, book_author, book_description, is_read 
                                  FROM favorites WHERE user_id=? ORDER BY added_at DESC''',
                                  (user_id,)).fetchall()
    else:
        favorites = conn.execute('''SELECT book_name, book_author, book_description, is_read 
                                  FROM favorites WHERE user_id=? AND is_read=? ORDER BY added_at DESC''',
                                  (user_id, is_read)).fetchall()
    conn.close()
    return favorites

def remove_from_favorites(user_id, book_name, book_author):
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''DELETE FROM favorites 
                   WHERE user_id=? AND book_name=? AND book_author=?''',
                   (user_id, book_name, book_author))
    conn.commit()
    conn.close()

def mark_as_read(user_id, book_name, book_author):
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''UPDATE favorites SET is_read=1 
                   WHERE user_id=? AND book_name=? AND book_author=?''',
                   (user_id, book_name, book_author))
    conn.commit()
    conn.close()

def mark_as_unread(user_id, book_name, book_author):
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''UPDATE favorites SET is_read=0 
                   WHERE user_id=? AND book_name=? AND book_author=?''',
                   (user_id, book_name, book_author))
    conn.commit()
    conn.close()


def set_first_interaction_date(user_id):
    """Устанавливает дату первого взаимодействия, если её ещё нет"""
    from datetime import date
    
    conn = sqlite3.connect(DB_PATH)
    
    existing = conn.execute('''SELECT first_interaction_date FROM user_stats 
                              WHERE user_id=?''', (user_id,)).fetchone()
    
    if not existing:
        today = date.today().strftime('%Y-%m-%d')
        conn.execute('''INSERT INTO user_stats (user_id, first_interaction_date) 
                       VALUES (?, ?)''', (user_id, today))
        conn.commit()
    
    conn.close()


def get_days_since_first_interaction(user_id):
    """Возвращает количество дней с первого взаимодействия"""
    from datetime import date, datetime
    
    conn = sqlite3.connect(DB_PATH)
    result = conn.execute('''SELECT first_interaction_date FROM user_stats 
                            WHERE user_id=?''', (user_id,)).fetchone()
    conn.close()
    
    if not result:
        return 0
    
    first_date = datetime.strptime(result[0], '%Y-%m-%d').date()
    today = date.today()
    
    return (today - first_date).days


def calculate_closeness_level(user_id):
    """Рассчитывает уровень близости пользователя"""
    
    days_passed = get_days_since_first_interaction(user_id)
    favorites_count = len(get_favorites(user_id))
    total_books_seen = get_total_booksdb(user_id)
    
    closeness_score = (days_passed * 0.3) + (favorites_count * 2) + (total_books_seen * 0.1)
    
    if closeness_score < 5:
        return "новичок"
    elif closeness_score < 15:
        return "interestedinyou"
    else:
        return "friend"


def get_closeness_level(user_id):
    """Публичная функция для получения уровня близости"""
    set_first_interaction_date(user_id)
    return calculate_closeness_level(user_id)
