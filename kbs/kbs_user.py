from aiogram import types

# def rand_startkb():
#     buttons = [
#         [types.InlineKeyboardButton(text='Выбрать книгу', callback_data = 'choose_book'),
#         types.InlineKeyboardButton(text='Узнать больше', callback_data = 'learn_more')]
#         ]
#     if random.randint(1, 100) <= 15:
#         art_button = types.InlineKeyboardButton(text = 'Кое-что загадочное', callback_data='rare_art')
#         buttons.append([art_button])

#     return types.InlineKeyboardMarkup(inline_keyboard = buttons)

kb_start = types.InlineKeyboardMarkup(
        inline_keyboard=[
            [types.InlineKeyboardButton(text='Выбрать книгу', callback_data = 'choose_book'),
        types.InlineKeyboardButton(text='Узнать больше', callback_data = 'learn_more')],
        [types.InlineKeyboardButton(text='Избранное', callback_data = 'favorites')]
        ]
)

# kb_talk = types.InlineKeyboardMarkup(
#         inline_keyboard=[
#             [types.InlineKeyboardButton(text=' '),
#             types.InlineKeyboardButton(text=' '],
#             [types.InlineKeyboardButton(text=' '),
#             types.InlineKeyboardButton(text=' ')],
#             [types.InlineKeyboardButton(text=' ']
#         ]
# )
kb_uschoice = types.InlineKeyboardMarkup(
        inline_keyboard=[
            [types.InlineKeyboardButton(text='Да, сэр', callback_data = 'yesbook'),
            types.InlineKeyboardButton(text='Не совсем...', callback_data = 'cancel')
            ]
        ]
)

kb_bookchoice = types.InlineKeyboardMarkup(
        inline_keyboard=[
            [types.InlineKeyboardButton(text='Утреннее', callback_data = 'usmorning'),
            types.InlineKeyboardButton(text='Дневное', callback_data = 'usday')],
            [types.InlineKeyboardButton(text='Вечернее', callback_data = 'usevening'),
            types.InlineKeyboardButton(text='Ночное', callback_data = 'usnight')],
            [types.InlineKeyboardButton(text='Назад', callback_data = 'cancel')]
            ]
)

kb_nazad = types.InlineKeyboardMarkup(
        inline_keyboard=[
            [types.InlineKeyboardButton(text='Назад', callback_data = 'cancel')]
        ]
)

kb_again_morning = types.InlineKeyboardMarkup(
    inline_keyboard = [
        [
            types.InlineKeyboardButton(text='Назад', callback_data = 'usmorning_prev'),
            types.InlineKeyboardButton(text='Еще книгу', callback_data = 'usmorning'),
        ],
        [
            types.InlineKeyboardButton(text='В избранное', callback_data = 'add_fav_morning')
        ],
        [types.InlineKeyboardButton(text='В меню', callback_data = 'cancel')]
        ]
)

kb_again_day = types.InlineKeyboardMarkup(
    inline_keyboard = [
        [
            types.InlineKeyboardButton(text='Назад', callback_data = 'usday_prev'),
            types.InlineKeyboardButton(text='Еще книгу', callback_data = 'usday'),
        ],
        [
            types.InlineKeyboardButton(text='В избранное', callback_data = 'add_fav_day')
        ],
        [types.InlineKeyboardButton(text='В меню', callback_data = 'cancel')]
        ]
)

kb_again_evening = types.InlineKeyboardMarkup(
    inline_keyboard = [
        [
            types.InlineKeyboardButton(text='Назад', callback_data = 'usevening_prev'),
            types.InlineKeyboardButton(text='Eще книгу', callback_data = 'usevening'),
        ],
        [
            types.InlineKeyboardButton(text='В избранное', callback_data = 'add_fav_evening')
        ],
        [types.InlineKeyboardButton(text='В меню', callback_data = 'cancel')]
        ]
)

kb_again_night = types.InlineKeyboardMarkup(
    inline_keyboard = [
        [
            types.InlineKeyboardButton(text='Назад', callback_data = 'usnight_prev'),
            types.InlineKeyboardButton(text='Еще книгу', callback_data = 'usnight'),
        ],
        [
            types.InlineKeyboardButton(text='В избранное', callback_data = 'add_fav_night')
        ],
        [types.InlineKeyboardButton(text='В меню', callback_data = 'cancel')]
    ]
)

kb_first_book_morning = types.InlineKeyboardMarkup(
    inline_keyboard = [
        [
            types.InlineKeyboardButton(text='Еще книгу', callback_data = 'usmorning'),
            types.InlineKeyboardButton(text='В меню', callback_data = 'cancel'),
        ]
    ]
)

kb_first_book_day = types.InlineKeyboardMarkup(
    inline_keyboard = [
        [
            types.InlineKeyboardButton(text='Еще книгу', callback_data = 'usday'),
            types.InlineKeyboardButton(text='В меню', callback_data = 'cancel'),
        ]
    ]
)

kb_first_book_evening = types.InlineKeyboardMarkup(
    inline_keyboard = [
        [
            types.InlineKeyboardButton(text='Еще книгу', callback_data = 'usevening'),
            types.InlineKeyboardButton(text='В меню', callback_data = 'cancel'),
        ]
    ]
)

kb_first_book_night = types.InlineKeyboardMarkup(
    inline_keyboard = [
        [
            types.InlineKeyboardButton(text='Еще книгу', callback_data = 'usnight'),
            types.InlineKeyboardButton(text='В меню', callback_data = 'cancel'),
        ]
    ]
)

kb_favorites_main = types.InlineKeyboardMarkup(
    inline_keyboard = [
        [
            types.InlineKeyboardButton(text='Прочитано', callback_data = 'fav_read'),
            types.InlineKeyboardButton(text='Не прочитано', callback_data = 'fav_unread')
        ],
        [
            types.InlineKeyboardButton(text='Все избранное', callback_data = 'fav_all'),
            types.InlineKeyboardButton(text='В меню', callback_data = 'cancel')
        ]
    ]
)

kb_favorites_nav = types.InlineKeyboardMarkup(
    inline_keyboard = [
        [
            types.InlineKeyboardButton(text='Назад', callback_data = 'fav_prev'),
            types.InlineKeyboardButton(text='Вперед', callback_data = 'fav_next')
        ],
        [
            types.InlineKeyboardButton(text='Прочитано', callback_data = 'fav_mark_read'),
            types.InlineKeyboardButton(text='Удалить', callback_data = 'fav_remove')
        ],
        [
            types.InlineKeyboardButton(text='К списку избранного', callback_data = 'fav_back_to_list')
        ]
    ]
)
